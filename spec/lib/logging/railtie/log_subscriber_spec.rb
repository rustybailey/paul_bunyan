require 'spec_helper'

module Logging
  RSpec.describe LogSubscriber do
    let(:aggregator) { subject.send(:aggregator) }

    def preserving_event_lists
      original_events = LogSubscriber.action_controller_events.dup
      LogSubscriber.action_controller_events.clear
      yield
    ensure
      LogSubscriber.instance_variable_set(:@action_controller_events, original_events)
    end

    before do
      RequestStore.clear!
    end

    describe '.action_controller_event(event_name)' do
      around(:each) do |example|
        preserving_event_lists do
          example.run
        end
      end

      it 'must store the event name' do
        LogSubscriber.action_controller_event :foo
        expect(LogSubscriber.action_controller_events).to include :foo
      end

      it 'must only add one copy of each event name' do
        LogSubscriber.action_controller_event :foo
        LogSubscriber.action_controller_event :foo
        LogSubscriber.action_controller_event :bar
        LogSubscriber.action_controller_event :bar
        expect(LogSubscriber.action_controller_events).to contain_exactly :foo, :bar
      end
    end

    describe '.event_patterns' do
      it 'must return a set including all action_controller events in that namespace', aggregate_failures: true do
        LogSubscriber.action_controller_events.each do |event|
          expect(LogSubscriber.event_patterns).to include "#{event}.action_controller"
        end
      end
    end

    describe '.subscribe_to_events' do
      around(:each) do |example|
        preserving_event_lists do
          example.run
        end
      end

      it 'must add a subscripton for all action_controller events' do
        LogSubscriber.action_controller_event :nx_event
        LogSubscriber.subscribe_to_events
        expect(subscriber_classes_for('nx_event.action_controller')).
          to include LogSubscriber
      end
    end

    describe '#process_action(event)' do
      let(:event) {
        ActiveSupport::Notifications::Event.new(
          'process_action.action_controller',
          Time.now,
          Time.at(Time.now.to_f - 0.240),
          SecureRandom.hex(5),
          {
            :controller=>"FoosController",
            :action => "show",
            :params => {"controller"=>"foos", "action"=>"show", "id" => "42", "foo" => "bar"},
            :format => :html,
            :method => "GET",
            :path => "/foos/42",
            :request_id => "dfa6f7b5-8400-4572-a2f7-80504ed9d09a",
            :ip => '127.0.0.1',
            :status => 200,
            :view_runtime => 220.038,
            :db_runtime => 10.177,
          }.with_indifferent_access
        )
      }

      before do
        allow(::Logging.logger).to receive(:info)
        subject.process_action(event)
      end

      it 'it must log the contents of the aggregator to the specified logger at the info level' do
        expect(::Logging.logger).to have_received(:info)
      end

      it 'must set the method on the aggregator' do
        expect(aggregator.method).to eq 'GET'
      end

      it 'must set the controller on the aggregator' do
        expect(aggregator.controller).to eq 'FoosController'
      end

      it 'must set the action on the aggregator' do
        expect(aggregator.action).to eq 'show'
      end

      it 'must set the format on the aggregator' do
        expect(aggregator.format).to eq :html
      end

      it 'must set the path on the aggregator' do
        expect(aggregator.path).to eq '/foos/42'
      end

      it 'must set the request_id on the aggregator' do
        expect(aggregator.request_id).to eq "dfa6f7b5-8400-4572-a2f7-80504ed9d09a"
      end

      it 'must set the ip address on the aggregator' do
        expect(aggregator.ip).to eq '127.0.0.1'
      end

      it 'must set the status on the aggregator' do
        expect(aggregator.status).to eq 200
      end

      it 'must set the view time on the aggregator' do
        expect(aggregator.view).to eq 220.038
      end

      it 'must set the db time on the aggregator' do
        expect(aggregator.db).to eq 10.177
      end

      context 'extracting the params' do
        it 'must not include the ActionController internal params from the hash' do
          expect(aggregator.params).to_not include ActionController::LogSubscriber::INTERNAL_PARAMS
        end

        it 'must include params passed to the controller action' do
          expect(aggregator.params).to include "id" => "42", "foo" => "bar"
        end
      end
    end

    describe '#halted_callback(event)' do
      let(:event) {
        ActiveSupport::Notifications::Event.new(
          'halted_callback.action_controller',
          Time.now,
          Time.at(Time.now.to_f - 0.240),
          SecureRandom.hex(5),
          {filter: described_class}.with_indifferent_access
        )
      }

      before do
        subject.halted_callback(event)
      end

      it 'must set the halting_filter field on the request aggregator' do
        expect(aggregator.halting_filter).to eq 'Logging::LogSubscriber'
      end
    end

    describe '#send_file(event)' do
      let(:event) {
        ActiveSupport::Notifications::Event.new(
          'send_file.action_controller',
          Time.at(Time.now.to_f - 0.240),
          Time.now,
          SecureRandom.hex(5),
          {path: '/path/to/a/file'}.with_indifferent_access
        )
      }
      let(:file_data) { aggregator.sent_file }

      before do
        subject.send_file(event)
      end

      it "must set the path field on the request aggregator's sent_file object" do
        expect(file_data.path).to eq '/path/to/a/file'
      end

      it "must set the transfer_time on the request aggregator's sent_file object" do
        expect(file_data.transfer_time).to be_within(1).of(240)
      end
    end

    describe '#redirect_to(event)' do
      let(:event) {
        ActiveSupport::Notifications::Event.new(
          'redirect_to.action_controller',
          Time.now,
          Time.at(Time.now.to_f - 0.240),
          SecureRandom.hex(5),
          {location: 'https://example.com/another/resource'}.with_indifferent_access
        )
      }

      before do
        subject.redirect_to(event)
      end

      it 'must set the redirect_location field on the request aggregator' do
        expect(aggregator.redirect_location).to eq 'https://example.com/another/resource'
      end
    end

    describe '#send_data(event)' do
      let(:event) {
        ActiveSupport::Notifications::Event.new(
          'send_data.action_controller',
          Time.at(Time.now.to_f - 0.240),
          Time.now,
          SecureRandom.hex(5),
          {filename: '/path/to/a/file'}.with_indifferent_access
        )
      }
      let(:file_data) { aggregator.sent_data }

      before do
        subject.send_data(event)
      end

      it "must set the path field on the request aggregator's sent_file object" do
        expect(file_data.path).to eq '/path/to/a/file'
      end

      it "must set the transfer_time on the request aggregator's sent_file object" do
        expect(file_data.transfer_time).to be_within(1).of(240)
      end
    end
  end
end
