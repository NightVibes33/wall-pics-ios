#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

API_HOST = 'api.appstoreconnect.apple.com'
BUNDLE_ID = ENV.fetch('PRISM_APP_BUNDLE_ID', 'com.nightvibes.prism.39A8Q3T3TR')
GROUP_REFERENCE_NAME = ENV.fetch('PRISM_SUBSCRIPTION_GROUP_NAME', 'Prism Pro')

SUBSCRIPTIONS = [
  {
    product_id: 'prism_pro_yearly',
    name: 'Prism Pro Yearly',
    display_name: 'Yearly Pro',
    description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures for one year.',
    period: 'ONE_YEAR',
    group_level: 1
  },
  {
    product_id: 'prism_pro_monthly',
    name: 'Prism Pro Monthly',
    display_name: 'Monthly Pro',
    description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures for one month.',
    period: 'ONE_MONTH',
    group_level: 2
  }
].freeze

LIFETIME = {
  product_id: 'prism_pro_lifetime',
  name: 'Prism Pro Lifetime',
  display_name: 'Lifetime Pro',
  description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures with one payment.'
}.freeze

KEY_ID = ENV.fetch('APP_STORE_CONNECT_KEY_ID')
ISSUER_ID = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
PRIVATE_KEY = ENV.fetch('APP_STORE_CONNECT_API_KEY_P8')

if PRIVATE_KEY.strip.empty? || KEY_ID.strip.empty? || ISSUER_ID.strip.empty?
  warn 'Missing App Store Connect API key env. Required: APP_STORE_CONNECT_API_KEY_P8, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID.'
  exit 1
end

def b64url(data)
  Base64.urlsafe_encode64(data).delete('=')
end

def der_signature_to_raw(der_signature)
  sequence = OpenSSL::ASN1.decode(der_signature)
  raise 'Unexpected ECDSA signature format' unless sequence.is_a?(OpenSSL::ASN1::Sequence) && sequence.value.size == 2

  sequence.value.map do |integer|
    hex = integer.value.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    [hex].pack('H*').rjust(32, "\0")[-32, 32]
  end.join
end

def jwt
  now = Time.now.to_i
  header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
  payload = { iss: ISSUER_ID, iat: now, exp: now + (20 * 60), aud: 'appstoreconnect-v1' }
  signing_input = [b64url(JSON.generate(header)), b64url(JSON.generate(payload))].join('.')
  key = OpenSSL::PKey.read(PRIVATE_KEY)
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  signature = der_signature_to_raw(key.dsa_sign_asn1(digest))
  "#{signing_input}.#{b64url(signature)}"
end

TOKEN = jwt

def request(method, path, query: nil, body: nil, fatal: true)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?
  req_class = case method
              when :get then Net::HTTP::Get
              when :post then Net::HTTP::Post
              else raise "Unsupported HTTP method #{method}"
              end
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(req)
    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    ok = response.code.to_i.between?(200, 299)
    unless ok || !fatal
      warn "#{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
      warn JSON.pretty_generate(parsed)
      exit 1
    end
    [response.code.to_i, parsed]
  end
end

def attributes(record)
  record.fetch('attributes', {}) || {}
end

def list_all(path, query: {})
  code, parsed = request(:get, path, query: query.merge('limit' => '200'))
  raise "GET #{path} returned #{code}" unless code.between?(200, 299)

  parsed.fetch('data', [])
end

def create_optional(path, body, label)
  code, response = request(:post, path, body: body, fatal: false)
  if code.between?(200, 299) && response['data']
    puts "Created #{label}: #{JSON.generate(attributes(response.fetch('data')).merge('id' => response.fetch('data').fetch('id')))}"
    response.fetch('data')
  else
    warn "Could not create #{label}; HTTP #{code}"
    warn JSON.pretty_generate(response)
    nil
  end
end

apps = list_all('/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku'
})
app = apps.first
unless app
  warn "No App Store Connect app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
puts "App: #{attributes(app)['name'] || '(unknown)'} (#{BUNDLE_ID}) id=#{app_id}"

groups = list_all("/v1/apps/#{app_id}/subscriptionGroups")
group = groups.find { |candidate| attributes(candidate)['referenceName'].to_s == GROUP_REFERENCE_NAME } || groups.first
unless group
  body = {
    data: {
      type: 'subscriptionGroups',
      attributes: { referenceName: GROUP_REFERENCE_NAME },
      relationships: { app: { data: { type: 'apps', id: app_id } } }
    }
  }
  group = create_optional('/v1/subscriptionGroups', body, 'subscription group')
end
unless group
  warn 'Cannot continue without a subscription group.'
  exit 1
end
group_id = group.fetch('id')
puts "Using subscription group #{group_id}: #{attributes(group)['referenceName'] || GROUP_REFERENCE_NAME}"

create_optional('/v1/subscriptionGroupLocalizations', {
  data: {
    type: 'subscriptionGroupLocalizations',
    attributes: { name: 'Prism Pro', locale: 'en-US' },
    relationships: { subscriptionGroup: { data: { type: 'subscriptionGroups', id: group_id } } }
  }
}, 'subscription group localization')

existing_subscriptions = list_all("/v1/subscriptionGroups/#{group_id}/subscriptions")
created_or_existing_subs = []
SUBSCRIPTIONS.each do |spec|
  existing = existing_subscriptions.find { |sub| attributes(sub)['productId'].to_s == spec[:product_id] }
  sub = existing
  unless sub
    body = {
      data: {
        type: 'subscriptions',
        attributes: {
          name: spec[:name],
          productId: spec[:product_id],
          subscriptionPeriod: spec[:period],
          familySharable: false,
          reviewNote: 'Prism Pro unlocks unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures.',
          groupLevel: spec[:group_level],
          availableInAllTerritories: true
        },
        relationships: { group: { data: { type: 'subscriptionGroups', id: group_id } } }
      }
    }
    sub = create_optional('/v1/subscriptions', body, "subscription #{spec[:product_id]}")
  end
  next unless sub

  puts "Using subscription #{spec[:product_id]} id=#{sub.fetch('id')} state=#{attributes(sub)['state']}"
  created_or_existing_subs << [spec, sub]
  create_optional('/v1/subscriptionLocalizations', {
    data: {
      type: 'subscriptionLocalizations',
      attributes: { name: spec[:display_name], locale: 'en-US', description: spec[:description] },
      relationships: { subscription: { data: { type: 'subscriptions', id: sub.fetch('id') } } }
    }
  }, "subscription localization #{spec[:product_id]}")
end

existing_iaps = list_all("/v1/apps/#{app_id}/inAppPurchasesV2")
iap = existing_iaps.find { |candidate| attributes(candidate)['productId'].to_s == LIFETIME[:product_id] }
unless iap
  body = {
    data: {
      type: 'inAppPurchases',
      attributes: {
        name: LIFETIME[:name],
        productId: LIFETIME[:product_id],
        inAppPurchaseType: 'NON_CONSUMABLE',
        familySharable: false,
        reviewNote: 'Prism Pro Lifetime unlocks the same Pro features without renewal.'
      },
      relationships: { app: { data: { type: 'apps', id: app_id } } }
    }
  }
  iap = create_optional('/v2/inAppPurchases', body, "in-app purchase #{LIFETIME[:product_id]}")
end
if iap
  puts "Using IAP #{LIFETIME[:product_id]} id=#{iap.fetch('id')} state=#{attributes(iap)['state']}"
  create_optional('/v2/inAppPurchaseLocalizations', {
    data: {
      type: 'inAppPurchaseLocalizations',
      attributes: { name: LIFETIME[:display_name], locale: 'en-US', description: LIFETIME[:description] },
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap.fetch('id') } } }
    }
  }, "IAP localization #{LIFETIME[:product_id]}")
end

puts 'Creation pass complete. Pricing, screenshots, and review submission may still be required in App Store Connect before StoreKit returns products.'
