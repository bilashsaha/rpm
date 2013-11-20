# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/browser_monitoring"
require "new_relic/rack/browser_monitoring"
require 'base64'

class NewRelic::Agent::BrowserMonitoringTest < Test::Unit::TestCase
  include NewRelic::Agent::BrowserMonitoring

  def setup
    @config = {
      :beacon                 => 'beacon',
      :browser_key            => 'browserKey',
      :application_id         => '5, 6', # collector can return app multiple ids
      :'rum.enabled'          => true,
      :license_key            => "\0"  # no-op obfuscation key
    }
    NewRelic::Agent.config.apply_config(@config)
    NewRelic::Agent.instance.instance_eval do
      @beacon_configuration = NewRelic::Agent::BeaconConfiguration.new
    end

    # By default we expect our transaction to have a start time
    # All sorts of basics don't output without this setup initially
    NewRelic::Agent::TransactionState.reset(nil)
    current_transaction.start_time = Time.now
  end

  def teardown
    NewRelic::Agent::TransactionState.clear
    NewRelic::Agent.config.remove_config(@config)
    mocha_teardown
  end

  def test_js_errors_beta_default_gets_default_loader
    assert_equal "rum", NewRelic::Agent.config[:'browser_monitoring.loader']
  end

  def test_js_errors_beta_gets_full_loader
    with_config(:js_errors_beta => true) do
      assert_equal "full", NewRelic::Agent.config[:'browser_monitoring.loader']
    end
  end

  def test_js_errors_beta_off_gets_default_loader
    with_config(:js_errors_beta => false) do
      assert_equal "rum", NewRelic::Agent.config[:'browser_monitoring.loader']
    end
  end

  def test_auto_instrumentation_config_defaults_to_enabled
    assert NewRelic::Agent.config[:'browser_monitoring.auto_instrument']
  end

  def test_start_time_reset_each_request_when_auto_instrument_is_disabled
    controller = Object.new
    def controller.perform_action_without_newrelic_trace(method, options={});
      # noop; instrument me
    end
    def controller.newrelic_metric_path; "foo"; end
    controller.extend ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    controller.extend ::NewRelic::Agent::BrowserMonitoring

    with_config(:'browser_monitoring.auto_instrument' => false) do
      controller.perform_action_with_newrelic_trace(:index)
      first_request_start_time = current_transaction.start_time

      controller.perform_action_with_newrelic_trace(:index)
      second_request_start_time = current_transaction.start_time

      # assert that these aren't the same time object
      # the start time should be reinitialized each request to the controller
      assert !(first_request_start_time.equal? second_request_start_time)
    end
  end

  def test_browser_timing_header_with_no_beacon_configuration
    NewRelic::Agent.instance.stubs(:beacon_configuration).returns( nil)
    assert_equal "", browser_timing_header
  end

  def test_browser_timing_header_with_rum_enabled_false
    with_config(:'rum.enabled' => false) do
      NewRelic::Agent.instance.stubs(:beacon_configuration).returns(NewRelic::Agent::BeaconConfiguration.new)
      assert_equal "", browser_timing_header
    end
  end

  def test_browser_timing_header_disable_all_tracing
    NewRelic::Agent.disable_all_tracing do
      assert_equal "", browser_timing_header
    end
  end

  def test_browser_timing_header_disable_transaction_tracing
    NewRelic::Agent.disable_transaction_tracing do
      assert_equal "", browser_timing_header
    end
  end

  def test_browser_timing_header_without_loader
    with_config(:js_agent_loader => '') do
      assert_equal "", browser_timing_header
    end
  end

  def test_browser_timing_header_without_rum_enabled
    with_config(:js_agent_loader => 'loader', :'rum.enabled' => false) do
      assert_equal "", browser_timing_header
    end
  end

  def test_browser_timing_header_with_loader
    with_config(:js_agent_loader => 'loader') do
      assert_has_js_agent_loader(browser_timing_header)
    end
  end

  def assert_has_js_agent_loader(header)
    assert_equal("\n<script type=\"text/javascript\">loader</script>",
                 header,
                 "expected new JS agent loader 'loader' but saw '#{header}'")
  end

  BEGINNING_OF_FOOTER = '<script type="text/javascript">window.NREUM||(NREUM={});NREUM.info='
  END_OF_FOOTER = '}</script>'

  def test_browser_timing_config
    with_config(:license_key => 'a' * 13) do
      browser_timing_header
      footer = browser_timing_config
      assert_has_text(BEGINNING_OF_FOOTER, footer)
      assert_has_text(END_OF_FOOTER, footer)
    end
  end

  def assert_has_text(snippet, footer)
    assert(footer.include?(snippet), "Expected footer to include snippet: #{snippet}, but instead was #{footer}")
  end

  def test_browser_timing_config_with_no_browser_key_rum_enabled
    with_config(:browser_key => '') do
      browser_timing_header
      NewRelic::Agent.instance.stubs(:beacon_configuration).returns(NewRelic::Agent::BeaconConfiguration.new)
      footer = browser_timing_config
      assert_equal "", footer
    end
  end

  def test_browser_timing_config_with_no_browser_key_rum_disabled
    with_config(:'rum.enabled' => false) do
      browser_timing_header
      NewRelic::Agent.instance.stubs(:beacon_configuration).returns(NewRelic::Agent::BeaconConfiguration.new)
      footer = browser_timing_config
      assert_equal "", footer
    end
  end

  def test_browser_timing_config_with_rum_enabled_not_specified
    footer = browser_timing_config
    beginning_snippet = BEGINNING_OF_FOOTER
    assert_has_text(BEGINNING_OF_FOOTER, footer)
    assert_has_text(END_OF_FOOTER, footer)
  end

  def test_browser_timing_config_with_no_beacon_configuration
    browser_timing_header
    NewRelic::Agent.instance.stubs(:beacon_configuration).returns( nil)
    footer = browser_timing_config
    assert_equal "", footer
  end

  def test_browser_timing_config_disable_all_tracing
    browser_timing_header
    footer = nil
    NewRelic::Agent.disable_all_tracing do
      footer = browser_timing_config
    end
    assert_equal "", footer
  end

  def test_browser_timing_config_disable_transaction_tracing
    browser_timing_header
    footer = nil
    NewRelic::Agent.disable_transaction_tracing do
      footer = browser_timing_config
    end
    assert_equal "", footer
  end

  def test_browser_timing_config_browser_key_missing
    with_config(:browser_key => '') do
      fake_config = mock('beacon configuration')
      NewRelic::Agent.instance.stubs(:beacon_configuration).returns(fake_config)
      fake_config.expects(:nil?).returns(false)
      fake_config.expects(:enabled?).returns(true)
      self.expects(:generate_footer_js).never
      assert_equal('', browser_timing_config, "should not return a footer when there is no key")
    end
  end

  def test_generate_footer_js_null_case
    current_transaction.start_time = nil
    assert_equal('', generate_footer_js(NewRelic::Agent.instance.beacon_configuration), "should not send javascript when there is no start time")
  end

  def test_generate_footer_js_with_start_time
    with_config(:browser_key => 'a' * 40) do
      fake_bc = mock('beacon configuration')
      NewRelic::Agent.instance.stubs(:beacon_configuration).returns(fake_bc)
      self.expects(:footer_js_string).with(NewRelic::Agent.instance.beacon_configuration).returns('footer js')
      assert_equal('footer js', generate_footer_js(NewRelic::Agent.instance.beacon_configuration),
                   'should generate and return the footer JS when there is a start time')
    end
  end

  def test_browser_timing_config_with_loader
    with_config(:js_agent_loader => 'loader') do
      footer = browser_timing_config
      beginning_snippet = "\n<script type=\"text/javascript\">window.NREUM||(NREUM={});NREUM.info={\""
      ending_snippet = '}</script>'
      assert(footer.include?(beginning_snippet),
             "expected footer to include beginning snippet: '#{beginning_snippet}', but was '#{footer}'")
      assert(footer.include?(ending_snippet),
             "expected footer to include ending snippet: '#{ending_snippet}', but was '#{footer}'")
    end
  end

  def test_browser_monitoring_transaction_name_basic
    txn = NewRelic::Agent::Transaction.new
    txn.name = 'a transaction name'
    NewRelic::Agent::TransactionState.get.transaction = txn

    assert_equal('a transaction name', browser_monitoring_transaction_name, "should take the value from the thread local")
  end

  def test_browser_monitoring_transaction_name_empty
    txn = NewRelic::Agent::Transaction.new
    txn.name = ''
    NewRelic::Agent::TransactionState.get.transaction = txn

    assert_equal('', browser_monitoring_transaction_name, "should take the value even when it is empty")
  end

  def test_browser_monitoring_transaction_name_nil
    assert_equal('(unknown)', browser_monitoring_transaction_name, "should fill in a default when it is nil")
  end

  def test_browser_monitoring_transaction_name_when_tt_disabled
    with_config(:'transaction_tracer.enabled' => false) do
      in_transaction('disabled_transactions') do
        self.class.inspect
      end

      assert_match(/disabled_transactions/, browser_monitoring_transaction_name,
                   "should name transaction when transaction tracing disabled")
    end
  end

  def test_extra_data
    in_transaction do
      with_config(ANALYTICS_TXN_IN_PAGE => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_equal({:boo => "hoo"}, extra_data)
      end
    end
  end

  def test_extra_data_outside_transaction
    NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
    assert extra_data.empty?
  end

  def test_format
    assert_formatted({:a => "1", "b" => 2}, "a=1", "b=#2")
  end

  def test_format_extra_data_escaping
    assert_formatted({"semi;colon" => "gets;escaped"}, "semi:colon=gets:escaped")
    assert_formatted({"equal=key" => "equal=value"}, "equal-key=equal-value")
    assert_formatted({'"quoted"' => '"marks"'}, %Q['quoted'='marks'])
  end

  def test_format_extra_data_disallowed_types
    assert_formatted_empty({"nested" => { "hashes?" => "nope" }})
    assert_formatted_empty({"lists" => ["are", "they", "allowed?", "nope"]})
  end

  def assert_formatted(data, *expected)
    result = format_extra_data(data).split(";")
    expected.each do |expect|
      assert_includes(result, expect)
    end
  end

  def assert_formatted_empty(data)
    result = format_extra_data(data)
    assert_equal("", result)
  end

  def test_footer_js_data
    freeze_time
    in_transaction do
      with_config(ANALYTICS_TXN_IN_PAGE => true) do
        NewRelic::Agent.set_user_attributes(:user => "user")

        txn = NewRelic::Agent::Transaction.current
        txn.stubs(:queue_time).returns(0)
        txn.stubs(:start_time).returns(Time.now - 10)
        txn.name = 'most recent transaction'

        state = NewRelic::Agent::TransactionState.get
        state.request_token = '0123456789ABCDEF'
        state.request_guid = 'ABC'

        data = js_data(NewRelic::Agent.instance.beacon_configuration)
        expected = {
          "beacon"          => "beacon",
          "errorBeacon"     => "",
          "licenseKey"      => "browserKey",
          "applicationID"   => "5, 6",
          "transactionName" => pack("most recent transaction"),
          "queueTime"       => 0,
          "applicationTime" => 10000,
          "ttGuid"          => "ABC",
          "agentToken"      => "0123456789ABCDEF",
          "agent"           => "",
          "extra"           => pack("user=user")
        }

        assert_equal(expected, data)

        js = footer_js_string(NewRelic::Agent.instance.beacon_configuration)
        expected.each do |key, value|
          assert_match(/"#{key.to_s}":#{formatted_for_matching(value)}/, js)
        end
      end
    end
  end

  ANALYTICS_ENABLED = :'analytics_events.enabled'
  ANALYTICS_TXN_ENABLED = :'analytics_events.transactions.enabled'
  ANALYTICS_TXN_IN_PAGE = :'capture_attributes.page_events'

  def test_js_data_doesnt_pick_up_extras_by_default
    in_transaction do
      NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
      assert_extra_data_is("")
    end
  end

  def test_js_data_picks_up_extras_when_configured
    in_transaction do
      with_config(ANALYTICS_ENABLED => true,
                  ANALYTICS_TXN_ENABLED => true,
                  ANALYTICS_TXN_IN_PAGE => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("boo=hoo")
      end
    end
  end

  def test_js_data_ignores_extras_if_no_analytics
    in_transaction do
      with_config(ANALYTICS_ENABLED => false,
                  ANALYTICS_TXN_ENABLED => true,
                  ANALYTICS_TXN_IN_PAGE => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("")
      end
    end
  end

  def test_js_data_ignores_extras_if_no_transaction_analytics
    in_transaction do
      with_config(ANALYTICS_ENABLED => true,
                  ANALYTICS_TXN_ENABLED => false,
                  ANALYTICS_TXN_IN_PAGE => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("")
      end
    end
  end

  def test_js_data_ignores_extras_if_not_allowed_in_page
    in_transaction do
      with_config(ANALYTICS_ENABLED => true,
                  ANALYTICS_TXN_ENABLED => true,
                  ANALYTICS_TXN_IN_PAGE => false) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("")
      end
    end
  end

  def assert_extra_data_is(expected)
    data = js_data(NewRelic::Agent.instance.beacon_configuration)
    assert_equal pack(expected), data["extra"]
  end

  def pack(text)
    [text].pack("m0").gsub("\n", "")
  end

  def formatted_for_matching(value)
    case value
    when String
      %Q["#{value}"]
    when NilClass
      "null"
    else
      value
    end
  end

  def test_html_safe_if_needed_unsafed
    string = mock('string')
    # here to handle 1.9 encoding - we stub this out because it should
    # be handled automatically and is outside the scope of this test
    string.stubs(:respond_to?).with(:encoding).returns(false)
    string.expects(:respond_to?).with(:html_safe).returns(false)
    assert_equal(string, html_safe_if_needed(string))
  end

  def test_html_safe_if_needed_safed
    string = mock('string')
    string.expects(:respond_to?).with(:html_safe).returns(true)
    string.expects(:html_safe).returns(string)
    # here to handle 1.9 encoding - we stub this out because it should
    # be handled automatically and is outside the scope of this test
    string.stubs(:respond_to?).with(:encoding).returns(false)
    assert_equal(string, html_safe_if_needed(string))
  end

  def test_obfuscate_basic
    text = 'a happy piece of small text'
    key = (1..40).to_a
    NewRelic::Agent.instance.beacon_configuration.expects(:license_bytes).returns(key)
    output = obfuscate(NewRelic::Agent.instance.beacon_configuration, text)
    assert_equal('YCJrZXV2fih5Y25vaCFtZSR2a2ZkZSp/aXV1', output, "should output obfuscated text")
  end

  def test_obfuscate_long_string
    text = 'a happy piece of small text' * 5
    key = (1..40).to_a
    NewRelic::Agent.instance.beacon_configuration.expects(:license_bytes).returns(key)
    output = obfuscate(NewRelic::Agent.instance.beacon_configuration, text)
    assert_equal('YCJrZXV2fih5Y25vaCFtZSR2a2ZkZSp/aXV1YyNsZHZ3cSl6YmluZCJsYiV1amllZit4aHl2YiRtZ3d4cCp7ZWhiZyNrYyZ0ZWhmZyx5ZHp3ZSVuZnh5cyt8ZGRhZiRqYCd7ZGtnYC11Z3twZCZvaXl6cix9aGdgYSVpYSh6Z2pgYSF2Znxx', output, "should output obfuscated text")
  end

  def test_obfuscate_utf8
    text = "foooooééoooo - blah"
    key = (1..40).to_a
    NewRelic::Agent.instance.beacon_configuration.expects(:license_bytes).returns(key).at_least_once
    output = obfuscate(NewRelic::Agent.instance.beacon_configuration, text)
    assert_equal('Z21sa2ppxKHKo2RjYm4iLiRnamZg', output, "should output obfuscated text")

    unoutput = obfuscate(NewRelic::Agent.instance.beacon_configuration, Base64.decode64(output))
    assert_equal Base64.encode64(text).gsub("\n", ''), unoutput
  end

  def test_freezes_transaction_name_when_footer_is_written
    with_config(:license_key => 'a' * 13) do
      in_transaction do
        assert !NewRelic::Agent::Transaction.current.name_frozen?
        browser_timing_config
        assert NewRelic::Agent::Transaction.current.name_frozen?
      end
    end
  end
end
