module QuickNotify

  class Mailer < ActionMailer::Base

    def notification_email(notif)
      opts = notif.delivery_settings_for(:email)
      opts[:to] = notif.user.email
      opts[:subject] = notif.subject
      opts[:body] = notif.full_message || notif.message
      opts[:scope] = {notification: notif}
      app_email(opts)

    end

    def app_email(opts)
      @options = opts
      @scope = opts[:scope] || {}

      html_lay = opts[:html_layout] || QuickNotify.options[:email][:html_layout]
      html_tpl = opts[:html_template]
      has_html_template = !html_tpl.nil?
      has_html_layout = !html_lay.nil?

      text_body = opts[:text_body] || opts[:body]
      html_body = text_body.gsub(/\n/, "<br>")

      mail(
        to: opts[:to],
        subject: opts[:subject],
      ) do |format|
        if has_html_template
          format.html { render html_tpl, layout: html_lay }
        elsif has_html_layout
          format.html { render text: html_body, layout: html_lay }
        end
        format.text { render text: text_body }
      end
    end

  end

end
