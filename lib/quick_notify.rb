require "quick_notify/version"
require "quick_notify/notification"
require "quick_notify/device"
require "quick_notify/apns"
require "quick_notify/sender"
require "quick_notify/event"
require "quick_notify/eventable"
require "quick_notify/mailer"

module QuickNotify
  # Your code goes here...

  if defined?(Rails)
    # load configuration
    class Railtie < Rails::Railtie
      initializer "quick_notify.configure" do
        config_file = Rails.root.join("config", "quick_notify.yml")
        QuickNotify.configure(YAML.load_file(config_file)[Rails.env]) if File.exists?(config_file)
      end
    end
  end

  class << self

    def configure(opts)
      @options = opts.with_indifferent_access unless opts.nil?
      # set any default opts here
      if @options[:email]
        QuickNotify::Mailer.raise_delivery_errors = true
        QuickNotify::Mailer.smtp_settings = {
          authentication: @options[:email][:authentication],
          address: @options[:email][:address],
          port: @options[:email][:port],
          domain: @options[:email][:domain],
          user_name: @options[:email][:user_name],
          password: @options[:email][:password]
        }
      end
    end

    def options
      @options ||= {}
    end

    def log(msg)
      if defined? Rails
        Rails.logger.info(msg)
      else
        puts msg
      end
    end

  end
end
