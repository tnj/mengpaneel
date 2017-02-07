require "active_support/hash_with_indifferent_access"
require "mixpanel-ruby"

module Mengpaneel
  class Tracker < Mixpanel::Tracker
    attr_reader :token
    attr_reader :remote_ip
    attr_reader :distinct_id

    def initialize(token, remote_ip = nil)
      super(token)
      @people = People.new(self)

      @remote_ip = remote_ip

      @disable_all_events = false
      @disabled_events = []

      @properties = HashWithIndifferentAccess.new
      @properties["ip"] = @remote_ip if @remote_ip
    end

    def push(item)
      method_name, args = item
      send(method_name, *args)
    end

    def disable(events = nil)
      if events
        @disabled_events += events
      else
        @disable_all_events = true
      end
    end

    def disable_people_ip!
      @remote_ip = '0'
      @properties["ip"] = '0'
    end

    def identify(distinct_id)
      @distinct_id = DistinctId.new(distinct_id)
    end

    def register(properties)
      @properties.merge!(properties)
    end

    def register_once(properties, default_value = "None")
      @properties.merge!(properties) do |key, oldval, newval|
        oldval.nil? || oldval == default_value ? newval : oldval
      end
    end

    def unregister(property)
      @properties.delete(property)
    end

    def get_property(property)
      @properties[property]
    end

    def track(event, properties = {})
      return if @disable_all_events || @disabled_events.include?(event)

      properties = @properties.merge(properties)

      super(@distinct_id, event, properties)
    end

    %w(track_links track_forms alias set_config get_config).map(&:to_sym).each do |name|
      define_method(name) do |*args|
        # Not supported on server side
      end
    end

    class People < Mixpanel::People
      attr_reader :tracker

      def initialize(tracker)
        @tracker = tracker
        
        super(tracker.token)
      end

      %w(set set_once append track_charge clear_charges delete_user).map(&:to_sym).each do |method_name|
        define_method(method_name) do |*args|
          args.unshift(tracker.distinct_id) unless args.first.is_a?(DistinctId)
          super(*args)
        end
      end

      def update(message)
        if tracker.remote_ip == '0'
          message.delete('$ip')
        else
          message['$ip'] = tracker.remote_ip
        end

        super(message)
      end

      # mixpanel-ruby only handles hash, whereas Javascript handles string and hash.
      def increment(*args)
        args.shift if args.first.is_a?(DistinctId)
        case args.first
          when Hash
            super(tracker.distinct_id, *args)
          when String
            super(tracker.distinct_id, args[0] => args[1] || 1)
          else
            raise ArgumentError, 'The first argument of increment must be either a hash or a string'
        end
      end
    end
  end

  class DistinctId < String; end
end
