require 'sensu/base'
require 'sensu/extensions/handlers/relay'
require 'eventmachine'

describe Sensu::Extension::RelayConnectionHandler do

  around(:each) do |example|
    async_wrapper do
      host = Wizardvan::Test::Fixtures::HOST
      port = Wizardvan::Test::Fixtures::PORT
      EM.start_server(host, port, Wizardvan::Test::Helpers::TestServer)
      @connection = EM.connect(host, port, Sensu::Extension::RelayConnectionHandler)
      @connection.host = host
      @connection.port = port
      example.call
    end
  end

  it 'can connect to a metrics backend' do
    @connection.should be_an_instance_of(Sensu::Extension::RelayConnectionHandler)
    EM.next_tick do
      @connection.connected.should eq(true)
      async_done
    end
  end

  it 'can be closed' do
    @connection.close_connection
    @connection.connected.should eq(false)
    async_done
  end

  it 'can send data' do
    @connection.send_data('some data').should eq(9)
    async_done
  end

  it 'schedules a reconnect after timeout' do
    @connection.close_connection
    @connection.comm_inactivity_timeout.should be > 0
    async_done
  end

  it 'can schedule a reconnect' do
    @connection.close_connection
    @connection.schedule_reconnect.should be > 0
    async_done
  end

  it 'can reconnect' do
    @connection.close_connection
    @connection.reconnect(0)
    EM.next_tick do
      EM.next_tick do
        EM.next_tick do
          @connection.connected.should eq(true)
          async_done
        end
      end
    end
  end

end

describe Sensu::Extension::Endpoint do

  around(:each) do |example|
    async_wrapper do
      host = Wizardvan::Test::Fixtures::HOST
      port = Wizardvan::Test::Fixtures::PORT
      EM.start_server(host, port, Wizardvan::Test::Helpers::TestServer)
      @endpoint = Sensu::Extension::Endpoint.new('name',
                                                 Wizardvan::Test::Fixtures::HOST,
                                                 Wizardvan::Test::Fixtures::PORT)
      example.run
    end
  end

  it 'can be created' do
    @endpoint.should be_an_instance_of(Sensu::Extension::Endpoint)
    async_done
  end

  it 'can connect to a backend' do
    EM.next_tick do
      EM.next_tick do
        @endpoint.connection.connected.should eq(true)
        async_done
      end
    end
  end

  it 'returns the correct queue length' do
    @endpoint.queue << 'test'
    @endpoint.queue << 'test'
    @endpoint.queue_length.should eq(8)
    async_done
  end

  it 'can flush to net' do
    async_wrapper do
      EM.next_tick do
        EM.next_tick do
          @endpoint.queue << 'a' * 16385
          @endpoint.flush_to_net
          @endpoint.queue.length.should eq(0)
          async_done
        end
      end
    end
  end

  it 'can relay an event' do
    async_wrapper do
      EM.next_tick do
        EM.next_tick do
          @endpoint.queue << 'a' * 16384
          @endpoint.relay_event('event')
          @endpoint.queue.length.should eq(0)
          async_done
        end
      end
    end
  end

  it 'can be stopped' do
    async_wrapper do
      EM.next_tick do
        @endpoint.stop
        EM.next_tick do
          EM.next_tick do
            @endpoint.connection.connected.should eq(false)
            async_done
          end
        end
      end
    end
  end

end

describe ExponentialDecayTimer do

  MAX_RECONNECT_TIME = 500

  before do
    @timer = ExponentialDecayTimer.new
  end

  it 'returns a reconnect time below MAX_RECONNECT_TIME' do
    time0 = @timer.get_reconnect_time(MAX_RECONNECT_TIME, 0)
    time1 = @timer.get_reconnect_time(MAX_RECONNECT_TIME, 1)
    time0.should satisfy { |n| n > 0 }
    time1.should satisfy { |n| n > time0 }
  end

  it 'does not return a time > MAX_RECONNECT_TIME' do
    @timer.get_reconnect_time(MAX_RECONNECT_TIME, 11).should == MAX_RECONNECT_TIME
  end

end

describe Sensu::Extension::MetricEmitter do

  before(:each) do
    @emitter = Sensu::Extension::MetricEmitter.new()
  end

  it 'can be initialized' do
    @emitter.should be_an_instance_of(Sensu::Extension::MetricEmitter)
  end

  it 'can update a metric' do
    @emitter.update_metric('test', 1)
    @emitter.get_metric('test').should eq(1)
  end

  it 'can zero a metric' do
    @emitter.zero_metric('test')
    @emitter.get_metric('test').should eq(0)
  end

  it 'can create an event' do
    @emitter.event.should eq(Wizardvan::Test::Fixtures::EMPTY_METRICS_EVENT.to_json)
  end

  it 'can emit an event' do
    async_wrapper do
      host = Wizardvan::Test::Fixtures::HOST
      port = Wizardvan::Test::Fixtures::PORT
      EM.start_server(host, port, Wizardvan::Test::Helpers::TestServer)
      @emitter.host = host
      @emitter.port = port
      @emitter.update_metric('test', 1)
      @emitter.emit
      async_done
    end
  end

end

describe Sensu::Extension::Relay do

  let(:mutated_event) do
    Wizardvan::Test::Fixtures::MUTATED_EVENT
  end

  around(:each) do |example|
    extensions = Sensu::Extensions.new
    extensions.require_directory(
      # bleh really?
      File.expand_path('../../../../../../lib/sensu/extensions', __FILE__)
    )
    extensions.load_all
    @handler = extensions[:handlers]['relay']

    # In the spirit of integration tests, don't just mock this...
    @settings = Sensu::Settings.new
    @settings.load_file(Wizardvan::Test::Fixtures::SETTINGS_FILE)
    @handler.settings = @settings.to_hash

    example.run
  end

  it 'can be loaded by sensu' do
    @handler.should be_an_instance_of(Sensu::Extension::Relay)
    @handler.definition[:type].should eq('extension')
    @handler.definition[:name].should eq('relay')
  end

  it 'can be initialized' do
    async_wrapper do
      @handler.post_init
      async_done
    end
  end

  it 'can process a mutated event' do
    async_wrapper do
      @handler.post_init
      @handler.run(mutated_event) do |status, error|
        status.should eq('')
        error.should eq(0)
        async_done
      end
    end
  end

  it 'can be stopped' do
    async_wrapper do
      @handler.post_init
      @handler.stop do
        async_done
      end
    end
  end

end
