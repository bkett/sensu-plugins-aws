#!/usr/bin/env ruby
#
# check-redshift-events
#
# DESCRIPTION:
#   This plugin checks amazon redshift clusters for maintenance events
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
#
#   check for clusters in maint in us-east-1:
#   ./check-redshift-events.rb -a ${your access key} -s ${your secret access key} -r us-east-1
#
#   check for maint events on a single instance in us-east-1 (skip others):
#   ./check-redshift-events.rb -a ${your access key} -s ${your secret access key} -r us-east-1 -i ${your cluster name}
#
#   check for maint events on multiple instance in us-east-1 (skip others):
#   ./check-redshift-events.rb -a ${your access key} -s ${your secret access key} -r us-east-1 -i ${cluster1,cluster2,cluster3}
#
# NOTES:
#
# LICENSE:
#   Copyright (c) 2014, Tim Smith, tim@cozy.co
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require 'sensu-pulgins-aws/helpers'

class CheckRedshiftEvents < Sensu::Plugin::Check::CLI
  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (such as eu-west-1).',
         default: 'us-east-1'

  option :clusters,
         short: '-c CLUSTER_IDS',
         long: '--clusters CLUSTER_IDS',
         description: 'Comma separated list of clusters to check. Defaults to all clusters in the region',
         proc: proc { |a| a.split(',') },
         default: []

  # throw unknown message if the user passed us a missing instance
  def check_missing_clusters(clusters)
    #WTF is this statement? return me an array that contains the clusters not in all redshift clusters for this region?
    missing_clusters = clusters.select { |cluster| !@clusters.include?(cluster) }
    unknown("Passed cluster(s): #{missing_clusters.join(',')} not found") unless missing_clusters.empty?
  end

  # return an array of clusters that are in maintenance
  def clusters_in_maint(clusters)
    maint_clusters = []

    # fetch the last 2 hours of events for each cluster
    clusters.each do |cluster_name|
      events_record = @redshift.describe_events(start_time: (Time.now - 7200).iso8601, source_type: 'cluster', source_identifier: cluster_name)

      next if events_record[:events].empty?

      # if the last event is a start maint event then the cluster is still in maint
      maint_clusters.push(cluster_name) if events_record[:events][-1][:event_id] == 'REDSHIFT-EVENT-2003'
    end
    maint_clusters
  end

  def run
    begin
      # make sure passed clusters exist and only check those clusters
      @redshift = Helpers::Redshift.new config[:aws_region]
      @clusters = @redshift.get_relevant_clusters config[:clusters]
      unless config[:clusters].empty?
        check_missing_clusters(config[:clusters])
      end

      maint_clusters = clusters_in_maint(@clusters)
    rescue => e
      unknown "An error occurred processing AWS Redshift API: #{e.message}"
    end

    if maint_clusters.empty?
      ok
    else
      critical("Clusters in maintenance: #{maint_clusters.join(',')}")
    end
  end
end
