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
EXPECTED_PRODUCTS = %w[prism_pro_monthly prism_pro_yearly prism_pro_lifetime].freeze

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

def request(method, path, query: nil)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?
  req_class = method == :get ? Net::HTTP::Get : raise("Unsupported HTTP method #{method}")
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(req)
    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    unless response.code.to_i.between?(200, 299)
      warn "GET #{path} failed with HTTP #{response.code}"
      warn JSON.pretty_generate(parsed)
      exit 1
    end
    parsed
  end
end

def attributes(record)
  record.fetch('attributes', {}) || {}
end

apps = request(:get, '/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku',
  'limit' => '1'
})
app = apps.fetch('data', []).first
unless app
  warn "No App Store Connect app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
puts "App: #{attributes(app)['name'] || '(unknown)'} (#{BUNDLE_ID})"

found = {}

puts 'Subscription groups and subscriptions:'
groups = request(:get, "/v1/apps/#{app_id}/subscriptionGroups", query: { 'limit' => '200' })
groups.fetch('data', []).each do |group|
  group_attrs = attributes(group)
  puts "Group #{group.fetch('id')}: #{JSON.generate(group_attrs)}"
  subs = request(:get, "/v1/subscriptionGroups/#{group.fetch('id')}/subscriptions", query: { 'limit' => '200' })
  subs.fetch('data', []).each do |sub|
    attrs = attributes(sub)
    product_id = attrs['productId'].to_s
    found[product_id] = attrs.merge('kind' => 'subscription') if product_id != ''
    puts "- subscription #{JSON.generate(attrs.slice('name', 'productId', 'state', 'subscriptionPeriod', 'groupLevel'))}"
  end
end

puts 'In-app purchases:'
iaps = request(:get, "/v1/apps/#{app_id}/inAppPurchasesV2", query: { 'limit' => '200' })
iaps.fetch('data', []).each do |iap|
  attrs = attributes(iap)
  product_id = attrs['productId'].to_s
  found[product_id] = attrs.merge('kind' => 'in_app_purchase') if product_id != ''
  puts "- iap #{JSON.generate(attrs.slice('referenceName', 'productId', 'inAppPurchaseType', 'state'))}"
end

missing = EXPECTED_PRODUCTS.reject { |product_id| found.key?(product_id) }
puts "Expected products: #{EXPECTED_PRODUCTS.join(', ')}"
puts "Found expected products: #{(EXPECTED_PRODUCTS - missing).join(', ')}"
puts "Missing expected products: #{missing.join(', ')}"

if missing.any?
  exit 2
end
