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

    use Middleware
    run!
  end
end
