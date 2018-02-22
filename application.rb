require 'faye/websocket'
require 'json'
require 'puma'
require 'redis'
require 'sinatra/base'
require 'thread'

# Load environment variables from .env if the file exists
if File.exist?('.env')
  File.foreach('.env') do |line|
    next if line.strip.empty?

    key, value = line.chomp.split('=', 2)
    ENV[key] = value
  end
end

module FishBowl
  module RedisFactory
    CHANNEL = 'fishbowl'
    REDIS_URI = URI.parse(ENV['REDIS'])

    # Build a new redis connection
    def self.build
      Redis.new(
        host: REDIS_URI.host,
        port: REDIS_URI.port,
        password: REDIS_URI.password
      )
    end
  end

  class Middleware
    KEEPALIVE = 15

    def initialize(app)
      @app     = app
      @clients = []
      @redis   = RedisFactory.build

      # In a separate thread, subscribe to the redis channel and broadcast to
      # each of the connected clients whenever messages are received.
      Thread.new do
        RedisFactory.build.subscribe(RedisFactory::CHANNEL) do |on|
          on.message do |_channel, message|
            @clients.each { |client| client.send(message) }
          end
        end
      end
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        client = Faye::WebSocket.new(env, nil, { ping: KEEPALIVE })

        client.on :open do |event|
          @clients << client
        end

        client.on :close do |event|
          @clients.delete(client)
          client = nil
        end

        client.rack_response
      else
        @app.call(env)
      end
    end
  end

  class Application < Sinatra::Base
    websocket =
      if ENV['RACK_ENV'] == 'production'
        'wss://fishbowl.culturehq.com'
      else
        'ws://localhost:4567'
      end

    csp = [
      "default-src 'none'",
      "connect-src 'self' #{websocket}",
      "script-src 'self'",
      "style-src 'self'",
      "img-src 'self'",
      "manifest-src 'self'",
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
      'report-uri https://culturehq.report-uri.com/r/d/csp/enforce'
    ]

    HEADERS = {
      'Content-Security-Policy' => csp.join('; '),
      'Expect-CT' => 'max-age=86400, report-uri="https://culturehq.report-uri.com/r/d/ct/reportOnly"',
      'Referrer-Policy' => 'same-origin',
      'Server' => 'CultureHQ.com',
      'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains; preload',
      'X-Download-Options' => 'noopen',
      'X-Frame-Options' => 'deny',
      'X-Permitted-Cross-Domain-Policies' => 'none'
    }.freeze

    def authorized?
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && compare(*@auth.credentials)
    end

    def compare(username, password)
      Rack::Utils.secure_compare(username, ENV['USERNAME']) &&
        Rack::Utils.secure_compare(password, ENV['PASSWORD'])
    end

    def protected!
      return if authorized?
      response['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      throw(:halt, [401, 'Unauthorized'])
    end

    set :server, 'puma'
    set :bind, '0.0.0.0'

    before do
      headers(HEADERS)
    end

    get '/' do
      protected!
      send_file('views/index.html')
    end

    get '/ping' do
      halt 200
    end

    post '/events' do
      RedisFactory.build.publish(RedisFactory::CHANNEL, request.body.read)
    end

    error(400) { halt 403 }
    error(402..599) { halt 403 }

    use Middleware
    use Rack::Deflater
    run!
  end
end
