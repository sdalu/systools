require 'net/https'
require 'json'


class PushOver
    @@app  = { }
    @@user = { }

    def self.register(id, token)
        @@app[id] = token
    end

    def self.user(id, token)
        @@user[id] = token
    end

    class Error             < StandardError ; end
    class ClientError       < Error         ; end
    class ServerError       < Error         ; end
    class LimitReachedError < ClientError   ; end

    MESSAGES_URI = URI.parse("https://api.pushover.net/1/messages.json").freeze

    def initialize(user_token, app_token)
        @user_token = case user_token
                      when Symbol   then @@user[user_token]
                      when String   then user_token
                      when NilClass then nil
                      else user_token.to_str
                      end
         @app_token = case app_token
                      when Symbol   then @@app[app_token]
                      when String   then app_token
                      when NilClass then nil
                      else app_token.to_str
                      end
        if @user_token.nil? || @app_token.nil?
            raise ArgumentError, "user and app tokens are requiered"
        end
    end

    def send(*args)
        send!(*args)
    rescue Error
        nil
    end

    def send!(message, title = nil, timestamp: Time::now.to_i, priority: 0)
        data = {
            :token     => @app_token,
            :user      => @user_token,
            :title     => title,
            :message   => message,
            :timestamp => timestamp,
            :priority  => priority
        }.reject {|k,v| v.nil? }

        req = Net::HTTP::Post::new(MESSAGES_URI.path)
        req.set_form_data(data)
        res = Net::HTTP::start(MESSAGES_URI.host, MESSAGES_URI.port,
                               :use_ssl     => true, 
                               :verify_mode => OpenSSL::SSL::VERIFY_PEER){|http|
                  http.request(req) 
              }
        
        case res
        when Net::HTTPSuccess
            JSON.parse(res.body)['request']
        when Net::HTTPTooManyRequests
            raise LimitReachedError
        when Net::HTTPClientError
            raise ClientError
        else    
            raise ServerError
        end
    end
end
