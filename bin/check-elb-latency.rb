#! /usr/bin/env ruby
#
# check-elb-latency
#
#
# DESCRIPTION:
#   This plugin checks the health of an Amazon Elastic Load Balancer.
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
#   Warning if any load balancer's latency is over 1 second, critical if over 3 seconds.
#   check-elb-latency --warning-over 1 --critical-over 3
#
#   Critical if "app" load balancer's latency is over 5 seconds, maximum of last one hour
#   check-elb-latency --elb-names app --critical-over 5 --statistics maximum --period 3600
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
require '../lib/helpers'

class CheckELBLatency < Sensu::Plugin::Check::CLI
  option :region,
         short:       '-r R',
         long:        '--region REGION',
         description: 'AWS region'

  option :elb_names,
         short:       '-l N',
         long:        '--elb-names NAMES',
         proc:        proc { |a| a.split(/[,;]\s*/) },
         description: 'Load balancer names to check. Separated by , or ;. If not specified, check all load balancers'

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
    option :"#{severity}_over",
           long:        "--#{severity}-over SECONDS",
           proc:        proc(&:to_f),
           description: "Trigger a #{severity} if latancy is over specified seconds"
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  
  def check_latency(elb)
    metric_conf = {
                    name: 'Latency',
                    aws_obj_name: elb.name,
                    dimension_name: 'LoadBalancerName' 
                  }
    ew = Helpers::ELBWatch.new(config, metric_conf, 'Seconds')
    metric_value = ew.get_latest_value
    if metric_value < 0
      if @elbs.size == 1
        @severities[:warning] = true
        return @message += "; The load balancer has no alive nodes!"
      end
      return @message += "; load balancer #{elb.name} has no alive nodes!"
    end
    @severities.keys.each do |severity|
      threshold = config[:"#{severity}_over"]
      next unless threshold
      next if metric_value < threshold
      flag_alert severity,
                 "; #{@elbs.size == 1 ? nil : "#{elb.name}'s"} Latency is #{sprintf '%.3f', metric_value} seconds. (expected lower than #{sprintf '%.3f', threshold})" # rubocop:disable LineLength
      break
    end
  end

  def run
    @elbs = Helpers::ELB.new(config[:region], config[:elb_names]).elbs

    @message  = if @elbs.size == 1
                  @elbs.first.inspect
                else
                  "#{@elbs.size} load balancers total"
                end

    @severities = {
      critical: false,
      warning:  false
    }

    @elbs.each { |elb| check_latency elb }

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
