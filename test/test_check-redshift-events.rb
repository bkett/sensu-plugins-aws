require 'minitest/autorun'
require 'aws-sdk-v1'
require 'sensu-plugins-aws'
require_relative '../bin/check-redshift-events'

class CheckRedshiftEventsTest < Minitest::Unit::TestCase
  def test_run
    CheckRedshiftEvents.run
  end
end
