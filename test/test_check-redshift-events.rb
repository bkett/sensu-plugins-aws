require 'minitest/autorun'
require 'aws-sdk-v1'
require 'sensu-plugins-aws'
require_relative '../bin/check-redshift-events'

class CheckRedshiftEventsTest < Minitest::Test
  def setup
    AWS.stub!
  end

  def test_run
    @redshift = Helpers::Redshift.new('us-west-2')
    @redshift.client.stub_for(:describe_clusters)
    ARGV << "-r" << "us-west-2"
    @events = CheckRedshiftEvents.new#(ARGV)
    @events.run
    #assert true
  end
end
