require 'socket'

module QuickNotify

  class APNS

    attr_accessor :host, :port, :pass, :pem

    def initialize(opts)
      self.host = opts[:host]
      self.port = opts[:port]
      self.pass = opts[:pass]
      self.pem = opts[:pem][0] == '/' ? opts[:pem] : File.join(Rails.root, 'config', opts[:pem])
    end

    def write(data)
      retries = 2
      begin
        self.connect! unless self.connected?
        @ssl.write(data)
        QuickNotify.log "QuickNotify::APNS:: Wrote #{data.length} bytes to #{self.host}:#{self.port}" 
        return true
      rescue Errno::EPIPE, OpenSSL::SSL::SSLError, Errno::ECONNRESET
        self.disconnect!
        if (retries -= 1) > 0
          retry
        else
          QuickNotify.log "QuickNotify::APNS:: Failed to write #{data.length} bytes to #{self.host}:#{self.port} after 3 retries" 
          return false
        end
      end

    end

    def connect!
      context      = OpenSSL::SSL::SSLContext.new
      context.cert = OpenSSL::X509::Certificate.new(File.read(self.pem))
      context.key  = OpenSSL::PKey::RSA.new(File.read(self.pem), self.pass)

      @sock         = TCPSocket.new(self.host, self.port)
      @ssl          = OpenSSL::SSL::SSLSocket.new(@sock,context)
      @ssl.connect

      return true
    end

    def connected?
      return !@ssl.nil?
    end

    def disconnect!
      @ssl.close
      @sock.close
      @sock = nil
      @ssl = nil
    end

    class Notification
      attr_accessor :device_token, :alert, :badge, :sound, :other
      
      def initialize(device_token, message)
        self.device_token = device_token
        if message.is_a?(Hash)
          self.alert = message[:alert]
          self.badge = message[:badge]
          self.sound = message[:sound]
          self.other = message[:other]
        elsif message.is_a?(String)
          self.alert = message
        else
          raise "Notification needs to have either a hash or string"
        end
      end
          
      def package
        pt = self.packaged_token
        pm = self.packaged_message
        [0, 0, 32, pt, 0, pm.bytesize, pm].pack("ccca*cca*")
      end

      def size
        self.package.length
      end
    
      def packaged_token
        [device_token.gsub(/[\s|<|>]/,'')].pack('H*')
      end
    
      def packaged_message
        aps = {'aps'=> {} }
        aps['aps']['alert'] = self.alert if self.alert
        aps['aps']['badge'] = self.badge if self.badge
        aps['aps']['sound'] = self.sound if self.sound
        aps.merge!(self.other) if self.other
        aps.to_json
      end
      
    end
    
  end

end
