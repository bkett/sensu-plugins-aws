#! /usr/bin/env ruby
#
# check-rds-events
#
#
# DESCRIPTION:
#   This plugin checks rds clusters for critical events.
#   Due to the number of events types on RDS clusters the check searches for
#   events containing the text string 'has started' or 'is being'.  These events all have
#   accompanying completiion events and are impacting events
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk-v1
#   gem: sensu-plugin
#
# USAGE:
#  ./check-rds-events.rb -r ${you_region}
#
# NOTES:
#
# LICENSE:
#   Tim Smith <tim@cozy.co>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require '../lib/helpers'

class CheckRDSEvents < Sensu::Plugin::Check::CLI
  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (such as eu-west-1).',
         default: 'us-east-1'

  def run # rubocop:disable AbcSize

    begin
      # fetch all clusters identifiers
      rds = Helpers::RDS.new(config[:region]).client
      clusters = rds.describe_db_instances[:db_instances].map { |db| db[:db_instance_identifier] }
      maint_clusters = []

      # fetch the last 2 hours of events for each cluster
      clusters.each do |cluster_name|
        events_record = rds.describe_events(start_time: (Time.now - 7200).iso8601, source_type: 'db-instance', source_identifier: cluster_name)
        next if events_record[:events].empty?

        # if the last event is a start maint event then the cluster is still in maint
        maint_clusters.push(cluster_name) if events_record[:events][-1][:message] =~ /has started|is being|off-line|shutdown/
      end
    rescue => e
      unknown "An error occurred processing AWS RDS API: #{e.message}"
    end

    if maint_clusters.empty?
      ok
    else
      critical("Clusters w/ critical events: #{maint_clusters.join(',')}")
    end
  end
end
