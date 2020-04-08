# encoding: utf-8
# frozen_string_literal: true

require "jekyll"
require "jekyll-ical-tag/version"

module Jekyll
  class IcalTag < Liquid::Block
    require_relative "jekyll-ical-tag/event"
    require_relative "jekyll-ical-tag/calendar_parser"
    require_relative "jekyll-ical-tag/calendar_limiter"

    include Convertible

    def initialize(tag_name, markup, parse_context)
      super
      @markup = markup

      scan_attributes!
      set_limit!
      set_reverse!
      set_url!
      set_only!
      set_before_date!
      set_after_date!
    end

    def render(context)
      context.registers[:ical] ||= Hash.new(0)

      result = []

      context.stack do
        url = get_url_from_assigned_value(context) ||
              get_url_from_page_attributes(context) ||
              @url

        raise "No URL provided or in innapropriate form '#{url}'" unless is_valid_url?(url)

        puts "Fetching #{url}"

        parser = CalendarParser.new(url)
        parser = CalendarLimiter.new(parser, only: @only)
        parser = CalendarLimiter.new(parser, reverse: @reverse)
        parser = CalendarLimiter.new(parser, before_date: @before_date)
        parser = CalendarLimiter.new(parser, after_date: @after_date)
        parser = CalendarLimiter.new(parser, limit: @limit)

        events = parser.events
        length = events.length

        events.each_with_index do |event, index|
          context["event"] = {
            "index" => index,
            "uid" => event.uid.presence,
            "summary" => as_utf8(event.summary).presence,
            "description" => as_utf8(event.description).presence,
            "simple_html_description" => as_utf8(event.simple_html_description).presence,
            "location" => as_utf8(event.location).presence,
            "url" => as_utf8(event.url&.to_s.presence || event.description_urls.first).presence,
            "start_time" => event.dtstart&.to_time.presence,
            "end_time" => event.dtend&.to_time.presence,
            "attendees" => event.attendees,
          }

          context["forloop"] = {
            "name" => "ical",
            "length" => length,
            "index" => index + 1,
            "index0" => index,
            "rindex" => length - index,
            "rindex0" => length - index - 1,
            "first" => (index == 0),
            "last" => (index == length - 1),
          }

          result << nodelist.map do |n|
            if n.respond_to? :render
              n.render(context)
            else
              n
            end
          end.join
        end
      end

      result
    end

    private

    def is_valid_url?(url)
      !!(url =~ URI::regexp)
    end

    def get_url_from_page_attributes(context)
      # Dereference url from something like "page.calender_url" to the page's calendar_url
      dig_attrs = @url.split(".")
      dig_attrs[0] = dig_attrs[0].to_sym if dig_attrs[0].present?

      context.registers.dig(*dig_attrs) # will return result or nil (if not found)
    end

    def get_url_from_assigned_value(context)
      return unless scope = context.scopes.find { |scope| scope[@url] }

      # Dereference the URL if we were passed a variable name.
      scope[@url]
    end

    def as_utf8(str)
      return unless str

      str.force_encoding("UTF-8")
    end

    def scan_attributes!
      @attributes = {}
      @markup.scan(Liquid::TagAttributes) do |key, value|
        @attributes[key] = value
      end
    end

    def set_limit!
      @limit = nil
      @limit = @attributes["limit"].to_i if @attributes["limit"]
    end

    def set_reverse!
      @reverse = @attributes["order"] == "reverse"
    end

    def set_url!
      @url = @attributes["url"]
    end

    def set_only!
      only_future = @attributes["only_future"] == "true"
      only_past = @attributes["only_past"] == "true"

      raise "Set only_future OR only_past, not both" if only_future && only_past
      @only = case
        when only_future
          :future
        when only_past
          :past
        else
          :all
        end
    end

    def set_before_date!
      @before_date = begin
          if @attributes["before_date"]
            Time.parse(@attributes["before_date"])
          end
        rescue => e
          nil
        end
    end

    def set_after_date!
      @after_date = begin
          if @attributes["after_date"]
            Time.parse(@attributes["after_date"])
          end
        rescue => e
          nil
        end
    end
  end
end

Liquid::Template.register_tag("ical", Jekyll::IcalTag)
