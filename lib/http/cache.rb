require "time"
require "http/cache/cache_control"
require "http/cache/response_with_cache_behavior"
require "http/cache/request_with_cache_behavior"

module HTTP
  class Cache
    ALLOWED_CACHE_MODES      = [:public, :private].freeze

    class CacheModeError < CacheError; end

    attr_reader :request, :response

    def initialize(options)
      unless ALLOWED_CACHE_MODES.include?(options.cache[:mode])
        fail CacheModeError, "Invalid cache_mode #{options.cache[:mode]} supplied"
      end
      @cache_mode    = options.cache[:mode]
      @cache_adapter = options.cache[:adapter]
    end

    # @return [Response] a cached response that is valid for the request or
    #   the result of executing the provided block.
    def perform(request, options, &request_performer)
      req = RequestWithCacheBehavior.coerce(request)

      if req.invalidates_cache?
        invalidate_cache(req)

      elsif cached_resp = cache_lookup(req)
        return cached_resp unless cached_resp.stale?

        req.set_validation_headers!(cached_resp)
      end

      # cache miss! Do this the hard way...
      req.sent_at = Time.now
      act_resp = ResponseWithCacheBehavior.coerce(yield(req, options))

      act_resp.received_at  = Time.now
      act_resp.requested_at = req.sent_at

      if act_resp.status.not_modified? && cached_resp
        cached_resp.validated!(act_resp)
        store_in_cache(req, cached_resp)
        return cached_resp

      elsif req.cacheable? && act_resp.cacheable?
        store_in_cache(req, act_resp)
        return act_resp

      else
        return act_resp
      end
    end

    protected


    def cache_lookup(request)
      return nil if request.skips_cache?
      c = @cache_adapter.lookup(request)
      if c
        ResponseWithCacheBehavior.coerce(c)
      else
        nil
      end
    end

    def store_in_cache(request, response)
      @cache_adapter.store(request, response)
      nil
    end

    def invalidate_cache(request)
      @cache_adapter.invalidate(request.uri)
    end

  end
end