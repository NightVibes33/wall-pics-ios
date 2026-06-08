#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'bigdecimal'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

API_HOST = 'api.appstoreconnect.apple.com'
BUNDLE_ID = ENV.fetch('PRISM_APP_BUNDLE_ID', 'com.nightvibes.prism.39A8Q3T3TR')
GROUP_REFERENCE_NAME = ENV.fetch('PRISM_SUBSCRIPTION_GROUP_NAME', 'Prism Pro')
BASE_TERRITORY = ENV.fetch('PRISM_PRICE_TERRITORY', 'USA')
REVIEW_SCREENSHOT_PATH = ENV.fetch('PRISM_REVIEW_SCREENSHOT_PATH', File.expand_path('assets/prism_pro_review.png', __dir__))
REVIEW_NOTE = 'Prism Pro unlocks unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures. No special login is required for App Review.'
IAP_REVIEW_NOTE = 'Prism Pro Lifetime unlocks the same Pro features without renewal.'

SUBSCRIPTIONS = [
  {
    product_id: 'prism_pro_yearly',
    name: 'Prism Pro Yearly',
    display_name: 'Yearly Pro',
    description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures for one year.',
    period: 'ONE_YEAR',
    group_level: 1,
    price: ENV.fetch('PRISM_YEARLY_PRICE_USD', '9.99')
  },
  {
    product_id: 'prism_pro_monthly',
    name: 'Prism Pro Monthly',
    display_name: 'Monthly Pro',
    description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures for one month.',
    period: 'ONE_MONTH',
    group_level: 2,
    price: ENV.fetch('PRISM_MONTHLY_PRICE_USD', '1.99')
  }
].freeze

LIFETIME = {
  product_id: 'prism_pro_lifetime',
  name: 'Prism Pro Lifetime',
  display_name: 'Lifetime Pro',
  description: 'Unlimited 4K downloads, Live Photos, matching sets, 3D Spatial, and profile pictures with one payment.',
  price: ENV.fetch('PRISM_LIFETIME_PRICE_USD', '19.99')
}.freeze

KEY_ID = ENV.fetch('APP_STORE_CONNECT_KEY_ID')
ISSUER_ID = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
PRIVATE_KEY = ENV.fetch('APP_STORE_CONNECT_API_KEY_P8')

if PRIVATE_KEY.strip.empty? || KEY_ID.strip.empty? || ISSUER_ID.strip.empty?
  warn 'Missing App Store Connect API key env. Required: APP_STORE_CONNECT_API_KEY_P8, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID.'
  exit 1
end

unless File.file?(REVIEW_SCREENSHOT_PATH)
  warn "Missing review screenshot asset at #{REVIEW_SCREENSHOT_PATH}."
  exit 1
end

SCREENSHOT_BYTES = File.binread(REVIEW_SCREENSHOT_PATH)
SCREENSHOT_MD5 = Digest::MD5.hexdigest(SCREENSHOT_BYTES)
SCREENSHOT_FILE_NAME = File.basename(REVIEW_SCREENSHOT_PATH)

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

def parse_response_body(response)
  response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
end

def request(method, path, query: nil, body: nil, fatal: true)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?
  req_class = case method
              when :get then Net::HTTP::Get
              when :post then Net::HTTP::Post
              when :patch then Net::HTTP::Patch
              when :delete then Net::HTTP::Delete
              else raise "Unsupported HTTP method #{method}"
              end

  attempts = 0
  loop do
    attempts += 1
    req = req_class.new(uri)
    req['Authorization'] = "Bearer #{TOKEN}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body) if body

    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
      raise if attempts >= 5

      warn "Retrying #{method.to_s.upcase} #{path} after #{e.class}."
      sleep(3 * attempts)
      next
    end

    return [response.code.to_i, {}] if response.code.to_i == 204

    parsed = parse_response_body(response)
    ok = response.code.to_i.between?(200, 299)
    if !ok && response.code.to_i == 429 && attempts < 5
      sleep(5 * attempts)
      next
    end
    unless ok || !fatal
      warn "#{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
      warn JSON.pretty_generate(parsed)
      exit 1
    end
    return [response.code.to_i, parsed]
  end
end

def upload_request(operation, bytes)
  uri = URI(operation.fetch('url'))
  req_class = case operation.fetch('method').to_s.upcase
              when 'PUT' then Net::HTTP::Put
              when 'POST' then Net::HTTP::Post
              else raise "Unsupported upload method #{operation['method']}"
              end
  req = req_class.new(uri)
  operation.fetch('requestHeaders', []).each do |header|
    req[header.fetch('name')] = header.fetch('value')
  end
  offset = operation.fetch('offset').to_i
  length = operation.fetch('length').to_i
  req.body = bytes.byteslice(offset, length)

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.request(req)
    return if response.code.to_i.between?(200, 299)

    warn "Upload operation failed with HTTP #{response.code}"
    warn response.body.to_s
    exit 1
  end
end

def attributes(record)
  record.fetch('attributes', {}) || {}
end

def list_all(path, query: {})
  data = []
  next_url = nil
  loop do
    if next_url
      uri = URI(next_url)
      code, parsed = request(:get, uri.path, query: URI.decode_www_form(uri.query || '').to_h)
    else
      code, parsed = request(:get, path, query: query.merge('limit' => query.fetch('limit', '200')))
    end
    raise "GET #{path} returned #{code}" unless code.between?(200, 299)

    data.concat(parsed.fetch('data', []))
    next_url = parsed.dig('links', 'next')
    break if next_url.nil? || next_url.to_s.empty?
  end
  data
end

def create_optional(path, body, label)
  code, response = request(:post, path, body: body, fatal: false)
  if code.between?(200, 299) && response['data']
    puts "Created #{label}: #{JSON.generate(attributes(response.fetch('data')).merge('id' => response.fetch('data').fetch('id')))}"
    response.fetch('data')
  elsif code == 409 || code == 422
    puts "#{label} already exists or cannot be recreated right now; HTTP #{code}."
    nil
  else
    warn "Could not create #{label}; HTTP #{code}"
    warn JSON.pretty_generate(response)
    nil
  end
end

def patch_optional(path, body, label)
  code, response = request(:patch, path, body: body, fatal: false)
  if code.between?(200, 299) && response['data']
    puts "Updated #{label}: #{JSON.generate(attributes(response.fetch('data')).merge('id' => response.fetch('data').fetch('id')))}"
    response.fetch('data')
  elsif code == 409 || code == 422
    puts "#{label} could not be updated right now; HTTP #{code}."
    puts JSON.pretty_generate(response)
    nil
  else
    warn "Could not update #{label}; HTTP #{code}"
    warn JSON.pretty_generate(response)
    nil
  end
end

def submit_optional(path, body, label)
  code, response = request(:post, path, body: body, fatal: false)
  if code.between?(200, 299) && response['data']
    puts "Submitted #{label}: #{JSON.generate(attributes(response.fetch('data')))}"
    response.fetch('data')
  elsif code == 409 || code == 422
    puts "#{label} submission not accepted by API right now; HTTP #{code}."
    puts JSON.pretty_generate(response)
    nil
  else
    warn "Could not submit #{label}; HTTP #{code}"
    warn JSON.pretty_generate(response)
    nil
  end
end

def territory_linkages
  @territory_linkages ||= list_all('/v1/territories', query: {
    'fields[territories]' => 'currency',
    'limit' => '200'
  }).map { |territory| { type: 'territories', id: territory.fetch('id') } }
end

def create_subscription_availability(subscription_id, product_id)
  create_optional('/v1/subscriptionAvailabilities', {
    data: {
      type: 'subscriptionAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        subscription: { data: { type: 'subscriptions', id: subscription_id } },
        availableTerritories: { data: territory_linkages }
      }
    }
  }, "subscription availability #{product_id}")
end

def create_iap_availability(iap_id, product_id)
  create_optional('/v1/inAppPurchaseAvailabilities', {
    data: {
      type: 'inAppPurchaseAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: iap_id } },
        availableTerritories: { data: territory_linkages }
      }
    }
  }, "IAP availability #{product_id}")
end

def preferred_english_record(records)
  records.find { |record| attributes(record)['locale'].to_s == 'en-US' }
end

def ensure_subscription_group_localization(group_id, name)
  records = list_all("/v1/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations", query: {
    'fields[subscriptionGroupLocalizations]' => 'name,locale'
  })
  existing = preferred_english_record(records)
  body = {
    data: {
      type: 'subscriptionGroupLocalizations',
      attributes: { name: name, locale: 'en-US' },
      relationships: { subscriptionGroup: { data: { type: 'subscriptionGroups', id: group_id } } }
    }
  }
  if existing
    id = existing.fetch('id')
    patch_optional("/v1/subscriptionGroupLocalizations/#{id}", {
      data: {
        type: 'subscriptionGroupLocalizations',
        id: id,
        attributes: body[:data][:attributes]
      }
    }, 'subscription group localization')
  else
    create_optional('/v1/subscriptionGroupLocalizations', body, 'subscription group localization')
  end
end

def patch_subscription_details(subscription_id, spec)
  patch_optional("/v1/subscriptions/#{subscription_id}", {
    data: {
      type: 'subscriptions',
      id: subscription_id,
      attributes: {
        name: spec[:name],
        familySharable: false,
        reviewNote: REVIEW_NOTE
      }
    }
  }, "subscription details #{spec[:product_id]}")
end

def ensure_subscription_localization(subscription_id, spec)
  records = list_all("/v1/subscriptions/#{subscription_id}/subscriptionLocalizations", query: {
    'fields[subscriptionLocalizations]' => 'name,locale,description'
  })
  existing = preferred_english_record(records)
  body = {
    data: {
      type: 'subscriptionLocalizations',
      attributes: { name: spec[:display_name], locale: 'en-US', description: spec[:description] },
      relationships: { subscription: { data: { type: 'subscriptions', id: subscription_id } } }
    }
  }
  if existing
    id = existing.fetch('id')
    patch_optional("/v1/subscriptionLocalizations/#{id}", {
      data: {
        type: 'subscriptionLocalizations',
        id: id,
        attributes: body[:data][:attributes]
      }
    }, "subscription localization #{spec[:product_id]}")
  else
    create_optional('/v1/subscriptionLocalizations', body, "subscription localization #{spec[:product_id]}")
  end
end

def patch_iap_details(iap_id)
  patch_optional("/v2/inAppPurchases/#{iap_id}", {
    data: {
      type: 'inAppPurchases',
      id: iap_id,
      attributes: {
        name: LIFETIME[:name],
        familySharable: false,
        reviewNote: IAP_REVIEW_NOTE
      }
    }
  }, "IAP details #{LIFETIME[:product_id]}")
end

def ensure_iap_localization(iap_id, spec)
  records = list_all("/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations", query: {
    'fields[inAppPurchaseLocalizations]' => 'name,locale,description'
  })
  existing = preferred_english_record(records)
  body = {
    data: {
      type: 'inAppPurchaseLocalizations',
      attributes: { name: spec[:display_name], locale: 'en-US', description: spec[:description] },
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap_id } } }
    }
  }
  if existing
    id = existing.fetch('id')
    patch_optional("/v1/inAppPurchaseLocalizations/#{id}", {
      data: {
        type: 'inAppPurchaseLocalizations',
        id: id,
        attributes: body[:data][:attributes]
      }
    }, "IAP localization #{spec[:product_id]}")
  else
    create_optional('/v1/inAppPurchaseLocalizations', body, "IAP localization #{spec[:product_id]}")
  end
end

def decimal_equal?(left, right)
  BigDecimal(left.to_s) == BigDecimal(right.to_s)
rescue ArgumentError
  false
end

def choose_price_point(points, target_price, label)
  chosen = points.find { |point| decimal_equal?(attributes(point)['customerPrice'], target_price) }
  unless chosen
    sample = points.map { |point| attributes(point)['customerPrice'] }.compact.take(20).join(', ')
    warn "No #{label} price point found for #{target_price} in #{BASE_TERRITORY}. Sample available prices: #{sample}"
    exit 1
  end
  puts "Using #{label} price #{attributes(chosen)['customerPrice']} #{BASE_TERRITORY} point=#{chosen.fetch('id')}"
  chosen
end

def subscription_price_points(subscription_id)
  list_all("/v1/subscriptions/#{subscription_id}/pricePoints", query: {
    'filter[territory]' => BASE_TERRITORY,
    'include' => 'territory',
    'fields[subscriptionPricePoints]' => 'customerPrice,proceeds,proceedsYear2,territory,equalizations',
    'limit' => '8000'
  })
end

def iap_price_points(iap_id)
  list_all("/v2/inAppPurchases/#{iap_id}/pricePoints", query: {
    'filter[territory]' => BASE_TERRITORY,
    'include' => 'territory',
    'fields[inAppPurchasePricePoints]' => 'customerPrice,proceeds,territory,equalizations',
    'limit' => '8000'
  })
end

def existing_subscription_prices(subscription_id)
  list_all("/v1/subscriptions/#{subscription_id}/prices", query: {
    'fields[subscriptionPrices]' => 'startDate,preserved,territory,subscriptionPricePoint',
    'limit' => '200'
  })
rescue StandardError => e
  warn "Could not read existing subscription prices for #{subscription_id}: #{e}"
  []
end

def create_subscription_price(subscription_id, price_point_id, product_id)
  create_optional('/v1/subscriptionPrices', {
    data: {
      type: 'subscriptionPrices',
      attributes: { preserveCurrentPrice: true },
      relationships: {
        subscription: { data: { type: 'subscriptions', id: subscription_id } },
        subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: price_point_id } }
      }
    }
  }, "subscription price #{product_id} #{price_point_id}")
end

def ensure_subscription_prices(subscription_id, product_id, target_price)
  existing = existing_subscription_prices(subscription_id)
  if existing.any?
    puts "Subscription #{product_id} already has #{existing.size} price records; keeping existing schedule."
    return
  end

  base_point = choose_price_point(subscription_price_points(subscription_id), target_price, product_id)
  code, equalizations = request(:get, "/v1/subscriptionPricePoints/#{base_point.fetch('id')}/relationships/equalizations", query: { 'limit' => '8000' }, fatal: false)
  unless code.between?(200, 299)
    warn "Could not list equalized subscription prices for #{product_id}; HTTP #{code}"
    warn JSON.pretty_generate(equalizations)
    exit 1
  end
  price_point_linkages = [{ 'type' => 'subscriptionPricePoints', 'id' => base_point.fetch('id') }]
  price_point_linkages.concat(equalizations.fetch('data', []))
  price_point_linkages.uniq! { |point| point.fetch('id') }
  puts "Creating #{price_point_linkages.size} territory price records for #{product_id}."
  price_point_linkages.each do |point|
    create_subscription_price(subscription_id, point.fetch('id'), product_id)
  end
end

def ensure_iap_price_schedule(iap_id, product_id, target_price)
  code, schedule = request(:get, "/v2/inAppPurchases/#{iap_id}/iapPriceSchedule", query: {
    'include' => 'baseTerritory,manualPrices,automaticPrices',
    'fields[inAppPurchasePriceSchedules]' => 'baseTerritory,manualPrices,automaticPrices',
    'limit[manualPrices]' => '50',
    'limit[automaticPrices]' => '50'
  }, fatal: false)
  if code.between?(200, 299) && schedule['data']
    relationship_ids = []
    %w[manualPrices automaticPrices].each do |relationship_name|
      relationship_ids.concat(Array(schedule.dig('data', 'relationships', relationship_name, 'data')).map { |item| item.fetch('id') })
    end
    included_ids = schedule.fetch('included', []).select { |item| item['type'].to_s == 'inAppPurchasePrices' }.map { |item| item.fetch('id') }
    price_count = (relationship_ids + included_ids).uniq.size
    puts "IAP #{product_id} has an existing price schedule with #{price_count} linked price records."
    return if price_count.positive?

    puts "IAP #{product_id} price schedule exists but has no linked price records; attempting to set target schedule."
  end

  point = choose_price_point(iap_price_points(iap_id), target_price, product_id)
  price_record_id = point.fetch('id')
  create_optional('/v1/inAppPurchasePriceSchedules', {
    data: {
      type: 'inAppPurchasePriceSchedules',
      relationships: {
        inAppPurchase: { data: { type: 'inAppPurchases', id: iap_id } },
        baseTerritory: { data: { type: 'territories', id: BASE_TERRITORY } },
        manualPrices: { data: [{ type: 'inAppPurchasePrices', id: price_record_id }] }
      }
    },
    included: [{
      type: 'inAppPurchasePrices',
      id: price_record_id,
      attributes: { startDate: nil, endDate: nil },
      relationships: {
        inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap_id } },
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: point.fetch('id') } }
      }
    }]
  }, "IAP price schedule #{product_id}")
end

def upload_asset_record(create_path:, commit_path_prefix:, owner_relationship:, resource_type:, label:)
  body = {
    data: {
      type: resource_type,
      attributes: { fileSize: SCREENSHOT_BYTES.bytesize, fileName: SCREENSHOT_FILE_NAME },
      relationships: owner_relationship
    }
  }
  code, response = request(:post, create_path, body: body, fatal: false)
  if code == 409 || code == 422
    puts "#{label} review screenshot reservation already exists or cannot be recreated; HTTP #{code}."
    puts JSON.pretty_generate(response)
    return nil
  end
  unless code.between?(200, 299) && response['data']
    warn "Could not create #{label} review screenshot reservation; HTTP #{code}"
    warn JSON.pretty_generate(response)
    exit 1
  end

  record = response.fetch('data')
  screenshot_id = record.fetch('id')
  operations = attributes(record).fetch('uploadOperations', [])
  puts "Uploading #{label} review screenshot #{SCREENSHOT_FILE_NAME} id=#{screenshot_id} parts=#{operations.size}."
  operations.each { |operation| upload_request(operation, SCREENSHOT_BYTES) }
  code, commit_response = request(:patch, "#{commit_path_prefix}/#{screenshot_id}", body: {
    data: {
      type: resource_type,
      id: screenshot_id,
      attributes: { uploaded: true, sourceFileChecksum: SCREENSHOT_MD5 }
    }
  }, fatal: false)
  unless code.between?(200, 299) && commit_response['data']
    warn "Could not commit #{label} review screenshot; HTTP #{code}"
    warn JSON.pretty_generate(commit_response)
    exit 1
  end
  puts "Committed #{label} review screenshot id=#{screenshot_id}."
  screenshot_id
end

def asset_complete?(record)
  state = attributes(record).dig('assetDeliveryState', 'state').to_s
  %w[COMPLETE UPLOAD_COMPLETE].include?(state)
end

def ensure_subscription_review_screenshot(subscription_id, product_id)
  code, response = request(:get, "/v1/subscriptions/#{subscription_id}/appStoreReviewScreenshot", query: {
    'fields[subscriptionAppStoreReviewScreenshots]' => 'fileSize,fileName,sourceFileChecksum,assetDeliveryState'
  }, fatal: false)
  if code.between?(200, 299) && response['data'] && asset_complete?(response.fetch('data'))
    puts "Subscription #{product_id} already has a review screenshot."
    return response.fetch('data').fetch('id')
  end

  upload_asset_record(
    create_path: '/v1/subscriptionAppStoreReviewScreenshots',
    commit_path_prefix: '/v1/subscriptionAppStoreReviewScreenshots',
    resource_type: 'subscriptionAppStoreReviewScreenshots',
    label: "subscription #{product_id}",
    owner_relationship: {
      subscription: { data: { type: 'subscriptions', id: subscription_id } }
    }
  )
end

def ensure_iap_review_screenshot(iap_id, product_id)
  code, response = request(:get, "/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot", query: {
    'fields[inAppPurchaseAppStoreReviewScreenshots]' => 'fileSize,fileName,sourceFileChecksum,assetDeliveryState'
  }, fatal: false)
  if code.between?(200, 299) && response['data'] && asset_complete?(response.fetch('data'))
    puts "IAP #{product_id} already has a review screenshot."
    return response.fetch('data').fetch('id')
  end

  upload_asset_record(
    create_path: '/v1/inAppPurchaseAppStoreReviewScreenshots',
    commit_path_prefix: '/v1/inAppPurchaseAppStoreReviewScreenshots',
    resource_type: 'inAppPurchaseAppStoreReviewScreenshots',
    label: "IAP #{product_id}",
    owner_relationship: {
      inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap_id } }
    }
  )
end

def refresh_subscription(subscription_id)
  code, response = request(:get, "/v1/subscriptions/#{subscription_id}", query: {
    'fields[subscriptions]' => 'name,productId,state,subscriptionPeriod,reviewNote,familySharable,groupLevel'
  }, fatal: false)
  code.between?(200, 299) ? response['data'] : nil
end

def refresh_iap(iap_id)
  code, response = request(:get, "/v2/inAppPurchases/#{iap_id}", query: {
    'fields[inAppPurchases]' => 'name,productId,inAppPurchaseType,state,reviewNote,familySharable'
  }, fatal: false)
  code.between?(200, 299) ? response['data'] : nil
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
puts "Using review screenshot #{REVIEW_SCREENSHOT_PATH} bytes=#{SCREENSHOT_BYTES.bytesize} md5=#{SCREENSHOT_MD5}"

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

ensure_subscription_group_localization(group_id, 'Prism Pro')

existing_subscriptions = list_all("/v1/subscriptionGroups/#{group_id}/subscriptions")
SUBSCRIPTIONS.each do |spec|
  sub = existing_subscriptions.find { |candidate| attributes(candidate)['productId'].to_s == spec[:product_id] }
  unless sub
    body = {
      data: {
        type: 'subscriptions',
        attributes: {
          name: spec[:name],
          productId: spec[:product_id],
          subscriptionPeriod: spec[:period],
          familySharable: false,
          reviewNote: REVIEW_NOTE,
          groupLevel: spec[:group_level],
          availableInAllTerritories: true
        },
        relationships: { group: { data: { type: 'subscriptionGroups', id: group_id } } }
      }
    }
    sub = create_optional('/v1/subscriptions', body, "subscription #{spec[:product_id]}")
  end
  next unless sub

  subscription_id = sub.fetch('id')
  puts "Using subscription #{spec[:product_id]} id=#{subscription_id} state=#{attributes(sub)['state']} target_price=#{spec[:price]}"
  patch_subscription_details(subscription_id, spec)
  create_subscription_availability(subscription_id, spec[:product_id])
  ensure_subscription_localization(subscription_id, spec)
  ensure_subscription_prices(subscription_id, spec[:product_id], spec[:price])
  ensure_subscription_review_screenshot(subscription_id, spec[:product_id])
  fresh = refresh_subscription(subscription_id)
  puts "Subscription #{spec[:product_id]} refreshed state=#{attributes(fresh || sub)['state']}"
  submit_optional('/v1/subscriptionSubmissions', {
    data: {
      type: 'subscriptionSubmissions',
      relationships: { subscription: { data: { type: 'subscriptions', id: subscription_id } } }
    }
  }, "subscription #{spec[:product_id]}")
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
        reviewNote: IAP_REVIEW_NOTE
      },
      relationships: { app: { data: { type: 'apps', id: app_id } } }
    }
  }
  iap = create_optional('/v2/inAppPurchases', body, "in-app purchase #{LIFETIME[:product_id]}")
end
if iap
  iap_id = iap.fetch('id')
  puts "Using IAP #{LIFETIME[:product_id]} id=#{iap_id} state=#{attributes(iap)['state']} target_price=#{LIFETIME[:price]}"
  patch_iap_details(iap_id)
  create_iap_availability(iap_id, LIFETIME[:product_id])
  ensure_iap_localization(iap_id, LIFETIME)
  ensure_iap_price_schedule(iap_id, LIFETIME[:product_id], LIFETIME[:price])
  ensure_iap_review_screenshot(iap_id, LIFETIME[:product_id])
  fresh = refresh_iap(iap_id)
  puts "IAP #{LIFETIME[:product_id]} refreshed state=#{attributes(fresh || iap)['state']}"
  submit_optional('/v1/inAppPurchaseSubmissions', {
    data: {
      type: 'inAppPurchaseSubmissions',
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap_id } } }
    }
  }, "IAP #{LIFETIME[:product_id]}")
end

puts 'Creation/finalization pass complete. Apple can take up to 1 hour to expose product metadata to StoreKit sandbox/TestFlight after API changes.'
