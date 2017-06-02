require "erb"
require "quick_notify/version"
require "quick_notify/event_listener"
require "quick_notify/notification"
require "quick_notify/device"
require "quick_notify/apns"
require "quick_notify/sender"
require "quick_notify/event"
require "quick_notify/eventable"
require "quick_notify/mailer"

module QuickNotify
  include EventListener

  if defined?(Rails)
    # load configuration
    class Railtie < Rails::Railtie
      initializer "quick_notify.configure" do
        config_file = Rails.root.join("config", "quick_notify.yml")
        if File.exists?(config_file)
          template = ERB.new(File.new(config_file).read).result(binding)
          QuickNotify.configure(YAML.load(template)[Rails.env])
        end
      end
    end
  end

  class << self

    def configure(opts)
      @options = opts.with_indifferent_access unless opts.nil?

      setup_classes
      setup_email
    end

    def options
      @options ||= {}
    end

    def setup_classes
      @options[:classes][:device] ||= '::Device'
      @options[:classes][:event] ||= '::Event'
      @options[:classes][:user] ||= '::User'
    end

    def setup_email
      # set any default opts here
      if @options[:email]
        QuickNotify::Mailer.raise_delivery_errors = true
        QuickNotify::Mailer.smtp_settings = {
          authentication: @options[:email][:authentication],
          address: @options[:email][:address],
          port: @options[:email][:port],
          domain: @options[:email][:domain],
          user_name: @options[:email][:user_name],
          password: @options[:email][:password],
          enable_starttls_auto: true
        }
        QuickNotify::Mailer.smtp_settings[:enable_starttls_auto] = true if !QuickNotify::Mailer.smtp_settings.key?(:enable_starttls_auto)
        QuickNotify::Mailer.default_options = {from: @options[:email][:from]}
      end
    end

    def classes
      @options[:classes]
    end

    def models
      @models ||= begin
        ModelMap.new(@options[:classes])
      end
    end

    def Device
      self.models[:device]
    end
    def Event
      self.models[:event]
    end
    def User
      self.models[:user]
    end

    def log(msg)
      if defined? Rails
        Rails.logger.info(msg)
      else
        puts msg
      end
    end

    def event_handlers
      @event_handlers ||= []
    end

    def event_after_handlers
      @event_after_handlers ||= []
    end


    ## utils

    def convert_text_to_html(text)
      # convert line breaks
      html = text.gsub(/\n/, "<br>")

      # convert links
      URI::extract(html, ["http", "https"]).each {|uri|
        html.gsub!(uri, "<a href=\"#{uri}\">#{uri}</a>")
      }
      return html
    end


  end

  class ModelMap

    def initialize(classes)
      @classes = classes
    end

    def [](val)
      val = val.to_sym
      return @classes[val].constantize
    end

  end
    
end
