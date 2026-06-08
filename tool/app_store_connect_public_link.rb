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
EXPECTED_BUILD_VERSION = ENV.fetch('PRISM_EXPECTED_BUILD_VERSION', '').strip
EXPECTED_BUILD_WAIT_SECONDS = ENV.fetch('PRISM_EXPECTED_BUILD_WAIT_SECONDS', '1800').to_i
EXPECTED_BUILD_WAIT_INTERVAL_SECONDS = ENV.fetch('PRISM_EXPECTED_BUILD_WAIT_INTERVAL_SECONDS', '60').to_i

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

def request_optional(method, path, query: nil, body: nil)
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
    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    [response.code.to_i, parsed]
  end
end

def attributes(record)
  record.fetch('attributes', {}) || {}
end

def fetch_sorted_builds(app_id)
  builds = request(:get, "/v1/apps/#{app_id}/builds", query: {
    'limit' => '200'
  })
  builds.fetch('data', []).sort_by do |build|
    Time.parse(attributes(build)['uploadedDate'].to_s) rescue Time.at(0)
  end.reverse
end

def valid_build?(build)
  attrs = attributes(build)
  !attrs['expired'] && attrs['processingState'].to_s.upcase == 'VALID'
end

def print_recent_builds(sorted_builds)
  puts 'Recent builds:'
  sorted_builds.take(8).each do |build|
    attrs = attributes(build)
    summary = attrs.slice(
      'version',
      'uploadedDate',
      'expired',
      'processingState',
      'usesNonExemptEncryption',
      'betaReviewState',
      'externalBuildState',
      'internalBuildState'
    )
    puts "- #{JSON.generate(summary)}"
  end
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

sorted_builds = fetch_sorted_builds(app_id)
print_recent_builds(sorted_builds)

latest_valid_build = nil
if EXPECTED_BUILD_VERSION.empty?
  latest_valid_build = sorted_builds.find { |build| valid_build?(build) }
else
  deadline = Time.now + EXPECTED_BUILD_WAIT_SECONDS
  loop do
    expected_build = sorted_builds.find { |build| attributes(build)['version'].to_s == EXPECTED_BUILD_VERSION }
    if expected_build && valid_build?(expected_build)
      latest_valid_build = expected_build
      battrs = attributes(latest_valid_build)
      puts "Using expected valid build: #{battrs['version']} uploaded #{battrs['uploadedDate']}"
      break
    end

    if expected_build
      attrs = attributes(expected_build)
      summary = attrs.slice(
        'version',
        'uploadedDate',
        'expired',
        'processingState',
        'usesNonExemptEncryption',
        'betaReviewState',
        'externalBuildState',
        'internalBuildState'
      )
      puts "Expected build #{EXPECTED_BUILD_VERSION} is not VALID yet: #{JSON.generate(summary)}"
    else
      puts "Expected build #{EXPECTED_BUILD_VERSION} not found yet."
    end

    if Time.now >= deadline
      warn "Expected build #{EXPECTED_BUILD_VERSION} did not become VALID within #{EXPECTED_BUILD_WAIT_SECONDS} seconds. Refusing to attach an older build."
      exit 2
    end

    sleep_seconds = [EXPECTED_BUILD_WAIT_INTERVAL_SECONDS, [(deadline - Time.now).to_i, 1].max].min
    puts "Waiting #{sleep_seconds}s before checking App Store Connect again."
    sleep sleep_seconds
    sorted_builds = fetch_sorted_builds(app_id)
    print_recent_builds(sorted_builds)
  end
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
all_groups = groups.fetch('data', [])
puts 'Beta groups:'
all_groups.each do |beta_group|
  gattrs = attributes(beta_group)
  puts "- #{gattrs['name']} internal=#{gattrs['isInternalGroup']} accessAllBuilds=#{gattrs['hasAccessToAllBuilds']} publicLinkEnabled=#{gattrs['publicLinkEnabled']}"
end

external_groups = all_groups.reject { |group| attributes(group)['isInternalGroup'] }
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
  all_groups << group
end

group_id = group.fetch('id')
puts "Beta group: #{attributes(group)['name']} (#{group_id})"

puts 'Recent build beta details:'
sorted_builds.take(5).each do |build|
  attrs = attributes(build)
  code, detail_response = request_optional(:get, "/v1/builds/#{build.fetch('id')}/buildBetaDetail", query: {
    'fields[buildBetaDetails]' => 'autoNotifyEnabled,internalBuildState,externalBuildState'
  })
  if code.between?(200, 299) && detail_response && detail_response['data']
    detail_attrs = attributes(detail_response.fetch('data'))
    puts "- build #{attrs['version']}: #{JSON.generate(detail_attrs)}"
  else
    puts "- build #{attrs['version']}: buildBetaDetail unavailable HTTP #{code}"
  end
end

puts 'Public beta group builds:'
group_builds = request(:get, "/v1/betaGroups/#{group_id}/builds", query: {
  'fields[builds]' => 'version,uploadedDate,expired,processingState,usesNonExemptEncryption',
  'limit' => '20'
})
group_builds.fetch('data', []).sort_by do |build|
  Time.parse(attributes(build)['uploadedDate'].to_s) rescue Time.at(0)
end.reverse.each do |build|
  attrs = attributes(build)
  puts "- #{JSON.generate(attrs.slice('version', 'uploadedDate', 'expired', 'processingState', 'usesNonExemptEncryption'))}"
end

def build_beta_detail(build_id)
  code, response = request_optional(:get, "/v1/builds/#{build_id}/buildBetaDetail", query: {
    'fields[buildBetaDetails]' => 'autoNotifyEnabled,internalBuildState,externalBuildState'
  })
  return nil unless code.between?(200, 299) && response && response['data']

  attributes(response.fetch('data'))
end

def beta_review_submission(build_id)
  code, response = request_optional(:get, "/v1/builds/#{build_id}/betaAppReviewSubmission", query: {
    'fields[betaAppReviewSubmissions]' => 'betaReviewState,submittedDate'
  })
  return [code, nil] unless code.between?(200, 299) && response && response['data']

  [code, attributes(response.fetch('data'))]
end

def attach_build_to_group(build, beta_group)
  gattrs = attributes(beta_group)
  code, response = request_optional(:post, "/v1/betaGroups/#{beta_group.fetch('id')}/relationships/builds", body: {
    data: [{ type: 'builds', id: build.fetch('id') }]
  })
  build_version = attributes(build)['version']
  if code.between?(200, 299) || code == 409
    puts "Ensured build #{build_version} is available to beta group #{gattrs['name']} (internal=#{gattrs['isInternalGroup']})."
    true
  else
    warn "Could not attach build #{build_version} to beta group #{gattrs['name']} (internal=#{gattrs['isInternalGroup']}); HTTP #{code}"
    warn JSON.pretty_generate(response)
    false
  end
end

if latest_valid_build
  latest_attrs = attributes(latest_valid_build)
  latest_detail = build_beta_detail(latest_valid_build.fetch('id'))
  puts "Latest valid beta detail: #{JSON.generate(latest_detail || {})}"
  submission_code, submission_attrs = beta_review_submission(latest_valid_build.fetch('id'))
  if submission_attrs
    puts "Latest valid beta review submission: #{JSON.generate(submission_attrs)}"
  else
    puts "Latest valid beta review submission unavailable HTTP #{submission_code}"
  end

  if latest_detail && latest_detail['externalBuildState'].to_s == 'READY_FOR_BETA_SUBMISSION' && submission_attrs.nil?
    puts "Submitting build #{latest_attrs['version']} for Beta App Review."
    submit_body = {
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: {
          build: {
            data: { type: 'builds', id: latest_valid_build.fetch('id') }
          }
        }
      }
    }
    submit_code, submit_response = request_optional(:post, '/v1/betaAppReviewSubmissions', body: submit_body)
    if submit_code.between?(200, 299) && submit_response && submit_response['data']
      puts "Beta App Review submission created: #{JSON.generate(attributes(submit_response.fetch('data')))}"
    else
      warn "Beta App Review submission failed with HTTP #{submit_code}"
      warn JSON.pretty_generate(submit_response)
    end
  end
end

if latest_valid_build
  puts 'Adding latest valid build to every beta group if not already attached.'
  failed_external_groups = []
  all_groups.uniq { |beta_group| beta_group.fetch('id') }.each do |beta_group|
    ok = attach_build_to_group(latest_valid_build, beta_group)
    failed_external_groups << attributes(beta_group)['name'] if !ok && !attributes(beta_group)['isInternalGroup']
  end
  if failed_external_groups.any?
    warn "Could not attach the build to these external beta groups: #{failed_external_groups.join(', ')}"
    warn 'This commonly means Beta App Review/export compliance/test information is still pending in App Store Connect.'
    exit 2
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
