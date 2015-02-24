#! /usr/bin/env ruby
#
# check-dynamodb-throttle
#
# DESCRIPTION:
#   Check DynamoDB throttle by CloudWatch and DynamoDB API.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk-v1
#   gem: time
#   gem: sensu-plugin
#
# USAGE:
#   Critical if session table's read throttle is over 50 for the last 5 minutes
#   check-dynamodb-throttle --table_names session --throttle-for read --critical-over 50 --statistics sum --period 300
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require 'time'
require '../lib/helpers'

class CheckDynamoDB < Sensu::Plugin::Check::CLI
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
         proc:        proc(&:to_i),
         description: 'CloudWatch metric statistics period'

  option :statistics,
         short:       '-S N',
         long:        '--statistics NAME',
         default:     :average,
         proc:        proc { |a| a.downcase.intern },
         description: 'CloudWatch statistics method'

  option :throttle_for,
         short:       '-c N',
         long:        '--throttle-for NAME',
         default:     [:read, :write],
         proc:        proc { |a| a.split(/[,;]\s*/).map { |n| n.downcase.intern } },
         description: 'Read/Write (or both) throttle to check.'

  %w(warning critical).each do |severity|
    option :"#{severity}_over",
           long:        "--#{severity}-over N",
           proc:        proc(&:to_f),
           description: "Trigger a #{severity} if throttle is over the given number"
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  def metric_hash metric_name, table_name
    {
      name: metric_name,
      aws_obj_name: table_name,
      dimension_name: 'TableName' 
    }
  end

  def check_throttle(table)
    config[:throttle_for].each do |r_or_w|
      metric_conf   = metric_hash("#{r_or_w.to_s.capitalize}ThrottleEvents", \
                                  table.name)
      dw = Helpers::DynamoWatch.new(config, metric_conf, 'Count') 
      metric_value = dw.get_latest_value

      @severities.keys.each do |severity|
        threshold = config[:"#{severity}_over"]
        next unless threshold
        next if metric_value < threshold
        flag_alert severity, "; On table #{table.name} #{r_or_w.to_s.capitalize}ThrottleEvents is #{metric_value} (higher_than #{threshold})"
        break
      end
    end
  end

  def run
    dynamo_db = Helpers::DynamoDB.new config[:region], config[:table_names]
    @message    = "#{dynamo_db.tables.size} tables total"
    @severities = {
      critical: false,
      warning: false
    }

    dynamo_db.tables.each { |table| check_throttle table }

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
