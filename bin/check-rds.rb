#! /usr/bin/env ruby
#
# check-rds
#
# DESCRIPTION:
#   Check RDS instance statuses by RDS and CloudWatch API.
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
#   Critical if DB instance "sensu-admin-db" is not on ap-northeast-1a
#   check-rds -i sensu-admin-db --availability-zone-critical ap-northeast-1a
#
#   Warning if CPUUtilization is over 80%, critical if over 90%
#   check-rds -i sensu-admin-db --cpu-warning-over 80 --cpu-critical-over 90
#
#   Critical if CPUUtilization is over 90%, maximum of last one hour
#   check-rds -i sensu-admin-db --cpu-critical-over 90 --statistics maximum --period 3600
#
#   Warning if memory usage is over 80%, maximum of last 2 hour
#   specifying "minimum" is intended actually since memory usage is calculated from CloudWatch "FreeableMemory" metric.
#   check-rds -i sensu-admin-db --memory-warning-over 80 --statistics minimum --period 7200
#
#   Disk usage, same as memory
#   check-rds -i sensu-admin-db --disk-warning-over 80 --period 7200
#
#   You can check multiple metrics simultaneously. Highest severity will be reported
#   check-rds -i sensu-admin-db --cpu-warning-over 80 --cpu-critical-over 90 --memory-warning-over 60 --memory-critical-over 80
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 github.com/y13i
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require 'time'
require 'sensu-plugins-aws/helpers'

class CheckRDS < Sensu::Plugin::Check::CLI
  option :region,
         short:       '-r R',
         long:        '--region REGION',
         description: 'AWS region',
         description: 'AWS Region (such as eu-west-1).',
         default: 'us-east-1'

  option :db_instance_id,
         short:       '-i N',
         long:        '--db-instance-id NAME',
         description: 'DB instance identifier',
         required:    true

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

  %w(warning critical).each do |severity|
    option :"availability_zone_#{severity}",
           long:        "--availability-zone-#{severity} AZ",
           description: "Trigger a #{severity} if availability zone is different than given argument"

    %w(cpu memory disk).each do |item|
      option :"#{item}_#{severity}_over",
             long:        "--#{item}-#{severity}-over N",
             proc:        proc(&:to_f),
             description: "Trigger a #{severity} if #{item} usage is over a percentage",
             default: 80
    end
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  def memory_total_bytes(instance_class)
    memory_total_gigabytes = {
      'db.t1.micro'    => 0.615,
      'db.m1.small'    => 1.7,
      'db.m3.medium'   => 3.75,
      'db.m3.large'    => 7.5,
      'db.m3.xlarge'   => 15.0,
      'db.m3.2xlarge'  => 30.0,
      'db.r3.large'    => 15.0,
      'db.r3.xlarge'   => 30.5,
      'db.r3.2xlarge'  => 61.0,
      'db.r3.4xlarge'  => 122.0,
      'db.r3.8xlarge'  => 244.0,
      'db.m2.xlarge'   => 17.1,
      'db.m2.2xlarge'  => 34.2,
      'db.m2.4xlarge'  => 68.4,
      'db.cr1.8xlarge' => 244.0,
      'db.m1.medium'   => 3.75,
      'db.m1.large'    => 7.5,
      'db.m1.xlarge'   => 15.0,
      'db.t2.micro'    => 1,
      'db.t2.small'    => 2,
      'db.t2.medium'   => 4
    }

    memory_total_gigabytes.fetch(instance_class) * 1024**3
  end

  def metric_hash metric_name
    {
      name: metric_name,
      aws_obj_name: @db_instance.id,
      dimension_name: 'DBInstanceIdentifier'
    }
  end

  def check_az(severity, expected_az)
    return if @db_instance.availability_zone_name == expected_az
    flag_alert severity, "; AZ is #{@db_instance.availability_zone_name} (expected #{expected_az})"
  end

  def check_cpu(severity, limit)
    cpu_metric = Helpers::RDSWatch.new(config, metric_hash('CPUUtilization'), 'Percent')
    cpu_metric_value = cpu_metric.get_latest_value
    return if cpu_metric_value < limit
    flag_alert severity, "; CPUUtilization is #{sprintf '%.2f', @cpu_metric_value}% (expected lower than #{limit}%)"
  end

  def check_memory(severity, limit)
    memory_metric = Helpers::RDSWatch.new(config, metric_hash('FreeableMemory'), 'Bytes')
    memory_metric_value = memory_metric.get_latest_value 
    provisioned_memory = memory_total_bytes @db_instance.db_instance_class
    used_memory = provisioned_memory - memory_metric_value
    memory_usage_percentage = used_memory / provisioned_memory * 100
    return if memory_usage_percentage < limit
    flag_alert severity, "; Memory usage is #{sprintf '%.2f', @memory_usage_percentage}% (expected lower than #{limit}%)"
  end

  def check_disk(severity, limit)
    disk_metric = Helpers::RDSWatch.new(config, metric_hash('FreeStorageSpace'), 'Bytes')
    disk_metric_value = disk_metric.get_latest_value
    provisioned_disk = @db_instance.allocated_storage * 1024**3
    used_disk = provisioned_disk - disk_metric_value
    disk_usage_percentage = used_disk / provisioned_disk * 100
    return if disk_usage_percentage < limit
    flag_alert severity, "; Disk usage is #{sprintf '%.2f', @disk_usage_percentage}% (expected lower than #{limit}%)"
  end

  def run
    AWS.start_memoizing
    @db_instance  = Helpers::RDS.new(config[:region]).rds.instances[config[:db_instance_id]]
    if not @db_instance.exists?
      raise AWS::RDS::Errors::DBInstanceNotFound
    end
    @message      = "#{config[:db_instance_id]}: "
    @severities   = {
      critical: false,
      warning:  false
    }

    @severities.keys.each do |severity|
      check_az severity, config[:"availability_zone_#{severity}"] if config[:"availability_zone_#{severity}"]

      %w(cpu memory disk).each do |item|
        send "check_#{item}", severity, config[:"#{item}_#{severity}_over"] if config[:"#{item}_#{severity}_over"]
      end
    end

    if %w(cpu memory disk).any? { |item| %w(warning critical).any? { |severity| config[:"#{item}_#{severity}_over"] } }
      @message += "(#{config[:statistics].to_s.capitalize} within #{config[:period]}s "
      @message += "between #{config[:end_time] - config[:period]} to #{config[:end_time]})"
    end
    AWS.stop_memoizing

    if @severities[:critical]
      critical @message
    elsif @severities[:warning]
      warning @message
    else
      ok @message
    end
  end
end
