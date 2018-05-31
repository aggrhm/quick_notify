module QuickNotify

  class Mailer < ActionMailer::Base

    def notification_email(notif)
      opts = notif.delivery_settings_for(:email)
      opts[:to] = notif.user.email
      opts[:subject] = notif.subject
      opts[:body] = notif.full_message || notif.message
      opts[:html_body] = notif.html_message
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
      html_body = opts[:html_body] || QuickNotify.convert_text_to_html(text_body)
      has_html_body = !html_body.nil?

      mail_opts = opts[:headers] || {}
      mail_opts[:to] = opts[:to]
      mail_opts[:cc] = opts[:cc] if opts[:cc]
      mail_opts[:bcc] = opts[:bcc] if opts[:bcc]
      mail_opts[:subject] = opts[:subject]
      mail(mail_opts) do |format|
        if has_html_template
          format.html { render html_tpl, layout: html_lay }
        elsif has_html_body
          format.html { render text: html_body, layout: html_lay }
        end
        if !text_body.nil?
          format.text { render text: text_body }
        end
      end
    end

  end

end
