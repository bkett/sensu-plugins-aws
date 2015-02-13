#! /usr/bin/env ruby
#
# check-dynamodb-capacity
#
# DESCRIPTION:
#   Check DynamoDB statuses by CloudWatch and DynamoDB API.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: time
#   gem: sensu-plugin
#
# USAGE:
#   Warning if any table's consumed read/write capacity is over 80%, critical if over 90%
#   check-dynamodb-capacity --warning-over 80 --critical-over 90
#
#   Critical if session table's consumed read capacity is over 90%, maximum of last one hour
#   check-dynamodb-capacity --table_names session --capacity-for read --critical-over 90 --statistics maximum --period 3600
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 github.com/y13i
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk'
require 'time'
require '../lib/helpers'

class CheckDynamoDB < Sensu::Plugin::Check::CLI

  option :access_key_id,
         short:       '-k N',
         long:        '--access-key-id ID',
         description: 'AWS access key ID'

  option :secret_access_key,
         short:       '-s N',
         long:        '--secret-access-key KEY',
         description: 'AWS secret access key'

  option :region,
         short:       '-r R',
         long:        '--region REGION',
         description: 'AWS region'

  option :table_names,
         short:       '-t N',
         long:        '--table-names NAMES',
         proc:        proc { |a| a.split(/[,;]\s*/) },
         description: 'Table names to check. Separated by , or ;. If not specified, check all tables'

  option :end_time,
         short:       '-t T',
         long:        '--end-time TIME',
         default:     Time.now,
         proc:        proc { |a| Time.parse a },
         description: 'CloudWatch metric statistics end time'

  option :period,
         short:       '-p N',
         long:        '--period SECONDS',
         default:     60,
         # #YELLOW
         proc:        proc(&:to_i),
         description: 'CloudWatch metric statistics period'

  option :statistics,
         short:       '-S N',
         long:        '--statistics NAME',
         default:     :average,
         proc:        proc { |a| a.downcase.intern },
         description: 'CloudWatch statistics method'

  option :capacity_for,
         short:       '-c N',
         long:        '--capacity-for NAME',
         default:     [:read, :write],
         proc:        proc { |a| a.split(/[,;]\s*/).map { |n| n.downcase.intern } },
         description: 'Read/Write (or both) capacity to check.'

  %w(warning critical).each do |severity|
    option :"#{severity}_over",
           long:        "--#{severity}-over N",
           # #YELLOW
           proc:        proc(&:to_f),
           description: "Trigger a #{severity} if consumed capacity is over a percentage"
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  def check_capacity(table)
    config[:capacity_for].each do |r_or_w|
      metric_name   = "Consumed#{r_or_w.to_s.capitalize}CapacityUnits"
      metric        = @cw.generate_metric metric_name, table.name, 'AWS/DynamoDB', 'TableName'
      metric_value  = @cw.get_latest_value metric, config
      percentage    = metric_value / table.send("#{r_or_w}_capacity_units").to_f * 100

      @severities.keys.each do |severity|
        threshold = config[:"#{severity}_over"]
        next unless threshold
        next if percentage < threshold
        flag_alert severity, "; On table #{table.name} consumed #{r_or_w} capacity is #{sprintf '%.2f', percentage}% (expected_lower_than #{threshold})"
        break
      end
    end
  end

  def run
    @cw = Helpers::CloudWatch.new config[:region]
    dynamo_db = Helpers::DynamoDB.new config[:region], config[:table_names]
    @message    = "#{dynamo_db.tables.size} tables total"
    @severities = {
      critical: false,
      warning:  false
    }

    dynamo_db.tables.each { |table| check_capacity table }

    @message += "; (#{config[:statistics].to_s.capitalize} within #{config[:period]} seconds "
    @message += "between #{config[:end_time] - config[:period]} to #{config[:end_time]})"

    if @severities[:critical]
      critical @message
    elsif @severities[:warning]
      warning @message
    else
      ok @message
    end
  end
end
