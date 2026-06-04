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
GROUP_NAME = ENV.fetch('PRISM_BETA_GROUP_NAME', 'Přism Public Beta')

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

def request(method, path, query: nil, body: nil)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?

  req_class = case method
              when :get then Net::HTTP::Get
              when :post then Net::HTTP::Post
              when :patch then Net::HTTP::Patch
              else raise "Unsupported HTTP method #{method}"
              end
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(req)
    return nil if response.code.to_i == 204

    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    unless response.code.to_i.between?(200, 299)
      warn "#{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
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
app_attrs = attributes(app)
puts "App: #{app_attrs['name'] || '(unknown)'} (#{BUNDLE_ID})"

builds = request(:get, "/v1/apps/#{app_id}/builds", query: {
  'fields[builds]' => 'version,uploadedDate,expired,processingState,usesNonExemptEncryption',
  'sort' => '-uploadedDate',
  'limit' => '10'
})
latest_valid_build = builds.fetch('data', []).find do |build|
  attrs = attributes(build)
  !attrs['expired'] && attrs['processingState'].to_s.upcase == 'VALID'
end
if latest_valid_build
  battrs = attributes(latest_valid_build)
  puts "Latest valid build: #{battrs['version']} uploaded #{battrs['uploadedDate']}"
else
  puts 'No VALID TestFlight build found yet. Public link can be enabled only after a compatible build is processed/approved.'
end

groups = request(:get, "/v1/apps/#{app_id}/betaGroups", query: {
  'fields[betaGroups]' => 'name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,publicLinkId,publicLinkLimitEnabled,publicLinkLimit,publicLink,feedbackEnabled',
  'limit' => '200'
})
external_groups = groups.fetch('data', []).reject { |group| attributes(group)['isInternalGroup'] }
group = external_groups.find { |candidate| attributes(candidate)['name'] == GROUP_NAME }

unless group
  body = {
    data: {
      type: 'betaGroups',
      attributes: {
        name: GROUP_NAME,
        isInternalGroup: false,
        hasAccessToAllBuilds: false,
        publicLinkEnabled: true,
        publicLinkLimitEnabled: false,
        feedbackEnabled: true
      },
      relationships: {
        app: {
          data: { type: 'apps', id: app_id }
        }
      }
    }
  }
  puts "Creating external beta group: #{GROUP_NAME}"
  group = request(:post, '/v1/betaGroups', body: body).fetch('data')
end

group_id = group.fetch('id')
puts "Beta group: #{attributes(group)['name']} (#{group_id})"

if latest_valid_build
  puts 'Adding latest valid build to beta group if not already attached.'
  begin
    request(:post, "/v1/betaGroups/#{group_id}/relationships/builds", body: {
      data: [{ type: 'builds', id: latest_valid_build.fetch('id') }]
    })
  rescue SystemExit
    warn 'Could not attach the build to the external group. This commonly means Beta App Review/export compliance/test info is still pending in App Store Connect.'
    raise
  end
end

patch_body = {
  data: {
    type: 'betaGroups',
    id: group_id,
    attributes: {
      publicLinkEnabled: true,
      publicLinkLimitEnabled: false,
      feedbackEnabled: true
    }
  }
}
puts 'Ensuring public link is enabled and open to anyone.'
request(:patch, "/v1/betaGroups/#{group_id}", body: patch_body)

fresh = request(:get, "/v1/betaGroups/#{group_id}", query: {
  'fields[betaGroups]' => 'name,isInternalGroup,publicLinkEnabled,publicLinkId,publicLinkLimitEnabled,publicLinkLimit,publicLink,feedbackEnabled'
}).fetch('data')
fattrs = attributes(fresh)
link = fattrs['publicLink'].to_s.strip

puts "Public link enabled: #{fattrs['publicLinkEnabled']}"
puts "Public link limit enabled: #{fattrs['publicLinkLimitEnabled']}"

if link.empty?
  warn 'No public TestFlight link was returned by App Store Connect yet.'
  warn 'Most likely blocker: the external TestFlight build still needs Beta App Review approval, export compliance, or TestFlight test information.'
  exit 2
end

puts "TESTFLIGHT_PUBLIC_LINK=#{link}"
