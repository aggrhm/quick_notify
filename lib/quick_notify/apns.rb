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
        # connect if not connected
        self.connect! unless self.connected?

        # try to write
        @ssl.write(data)
        @ssl.flush

        # check if anything available to read (timeout in half a second)
        if (result = IO.select([@ssl], nil, nil, 0.5))
          if result[0]
            bytes = @ssl.read(6)
            if bytes.length == 6
              # received response from Apple
              resp = bytes.unpack('CCN')
              QuickNotify.log "QuickNotify::APNS:: Received #{resp.to_s} from Apple Gateway. Disconnecting..."
              raise "Received Apple Error Response"
            end
          end
        end

        # timeout reached
        QuickNotify.log "QuickNotify::APNS:: Wrote #{data.length} bytes to #{self.host}:#{self.port}" 
        return true

      rescue Exception => e
        QuickNotify.log "QuickNotify::APNS:: Connection reset by Apple (#{e.message}). Potentially due to error in last notification"
        self.disconnect!
        if (retries -= 1) > 0
          retry
        else
          QuickNotify.log "QuickNotify::APNS:: Failed to write #{data.length} bytes to #{self.host}:#{self.port} after 3 attempts" 
          return false
        end

      end

    end

    def write2(data)
      retries = 2
      begin
        self.connect! unless self.connected?
        @ssl.write(data)
        QuickNotify.log "QuickNotify::APNS:: Wrote #{data.length} bytes to #{self.host}:#{self.port}" 
        return true
      rescue Errno::EPIPE, OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::ETIMEDOUT
        QuickNotify.log "QuickNotify::APNS:: Connection reset by Apple. Potentially due to error in last notification"
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
        items = []
        items << self.packaged_token
        items << self.packaged_message
        items << self.packaged_identifier
        items << self.packaged_expiration
        items << self.packaged_priority

        item_length = items.reduce(0) {|sz, item| sz += item.bytesize}

        #[0, 0, 32, pt, 0, pm.bytesize, pm].pack("ccca*cca*")
        frame = [2, item_length, items[0], items[1], items[2], items[3], items[4]].pack('CNa*a*a*a*a*')
        return frame
      end

      def size
        self.package.length
      end
    
      def packaged_token
        [1, 32, self.device_token.gsub(/[\s|<|>]/,'')].pack('CnH64')
      end
    
      def packaged_message
        aps = {'aps'=> {} }
        aps['aps']['alert'] = self.alert if self.alert
        aps['aps']['badge'] = self.badge if self.badge
        aps['aps']['sound'] = self.sound if self.sound
        aps.merge!(self.other) if self.other
        str = aps.to_json
        [2, str.bytesize, str].pack('Cna*')
      end

      def packaged_identifier
        [3, 4, Time.now.to_i].pack('CnN')
      end

      def packaged_expiration
        exp = Time.now + 1.day
        [4, 4, exp.to_i].pack('CnN')
      end

      def packaged_priority
        [5, 1, 10].pack('CnC')
      end
      
    end
    
  end

end
