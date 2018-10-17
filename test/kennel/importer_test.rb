# frozen_string_literal: true
require_relative "../test_helper"
require "kennel/importer"

SingleCov.covered!

describe Kennel::Importer do
  let(:importer) { Kennel::Importer.new(Kennel::Api.new("app", "api")) }

  describe "#import" do
    it "prints simple valid code" do
      response = { dash: { id: 123, title: "hello", created_by: "me", deleted: "yes" } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          title: -> { "hello" },
          id: -> { 123 }
        )
      RUBY
      code = "TestProject.new(parts: -> {[#{dash}]})"
      project = eval(code, binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
      project.parts.size.must_equal 1
    end

    it "prints complex elements" do
      response = { dash: { foo: [1, 2], bar: { baz: ["123", "foo", { a: 1 }] } } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          id: -> { 123 },
          bar: -> {
            {
              baz: [
                "123",
                "foo",
                {
                  a: 1
                }
              ]
            }
          },
          foo: -> {
            [
              1,
              2
            ]
          }
        )
      RUBY
    end

    it "prints null as nil" do
      response = { dash: { bar: { baz: nil } } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          id: -> { 123 },
          bar: -> {
            {
              baz: nil
            }
          }
        )
      RUBY
    end

    it "removes boring default values" do
      response = { dash: { id: 123, graphs: [{ definition: { foo: "bar", autoscale: true } }] } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          id: -> { 123 },
          graphs: -> {
            [
              {
                definition: {
                  foo: "bar"
                }
              }
            ]
          }
        )
      RUBY
    end

    it "can import a screen" do
      response = { id: 123, board_title: "hello" }
      stub_datadog_request(:get, "screen/123").to_return(body: response.to_json)
      dash = importer.import("screen", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Screen.new(
          self,
          board_title: -> { "hello" },
          id: -> { 123 }
        )
      RUBY
    end

    it "can import a monitor" do
      response = { id: 123, name: "hello", options: {} }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          escalation_message: -> { nil }
        )
      RUBY
    end

    it "flattens monitor options" do
      response = {
        id: 123,
        name: "hello",
        options: {
          notify_audit: true,
          locked: false,
          timeout_h: 0,
          include_tags: true,
          no_data_timeframe: nil,
          new_host_delay: 300,
          require_full_window: false,
          notify_no_data: false,
          renotify_interval: 120,
          escalation_message: nil,
          thresholds: {
            critical: 25.0
          },
          evaluation_delay: nil
        }
      }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          critical: -> { 25.0 },
          escalation_message: -> { nil },
          no_data_timeframe: -> { nil },
          notify_audit: -> { true },
          notify_no_data: -> { false },
          renotify_interval: -> { 120 },
          timeout_h: -> { 0 }
        )
      RUBY
    end

    it "fails when requesting an unsupported resource" do
      stub_datadog_request(:get, "wut/123").to_return(body: "{}")
      e = assert_raises(ArgumentError) { importer.import("wut", 123) }
      e.message.must_equal "wut is not supported"
    end
  end
end
