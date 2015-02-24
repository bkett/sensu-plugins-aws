#! /usr/bin/env ruby
#
# chwck-elb-sum-requests
#
# DESCRIPTION:
#   Check ELB Sum Requests by CloudWatch API.
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
#   Warning if any load balancer's sum request count is over 1000, critical if over 2000.
#   check-elb-sum-requests --warning-over 1000 --critical-over 2000
#
#   Critical if "app" load balancer's sum request count is over 10000, within last one hour
#   check-elb-sum-requests --elb-names app --critical-over 10000 --period 3600
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

class CheckELBSumRequests < Sensu::Plugin::Check::CLI
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
         default:     :sum,
         proc:        proc { |a| a.downcase.intern },
         description: 'CloudWatch statistics method'

  %w(warning critical).each do |severity|
    option :"#{severity}_over",
           long:        "--#{severity}-over COUNT",
           proc:        proc(&:to_f),
           description: "Trigger a #{severity} if sum requests is over specified count"
  end

  def flag_alert(severity, message)
    @severities[severity] = true
    @message += message
  end

  def metric_hash metric_name, elb_name
    {
      name: metric_name,
      aws_obj_name: elb_name,
      dimension_name: 'LoadBalancerName' 
    }
  end

  def check_sum_requests(elb)
    metric_conf =  metric_hash('RequestCount', elb.name)
    ew = Helpers::ELBWatch.new(config, metric_conf, 'Count')
    metric_value = ew.get_latest_value
    if metric_value < 0
      @message += "; load balancer #{elb.name} has no alive nodes!"
      if @elbs.size == 1
        @severities[:warning] = true
      end
    end
    @severities.keys.each do |severity|
      threshold = config[:"#{severity}_over"]
      next unless threshold
      next if metric_value < threshold
      flag_alert severity,
                 "; #{@elbs.size == 1 ? nil : "#{elb.inspect}'s"} Sum Requests is #{metric_value}. (expected lower than #{threshold})"
      break
    end
  end

  def run
    @elbs = Helpers::ELB.new(config[:region], config[:elb_names]).elbs
    @message  = if @elbs.size == 1
                  @elbs.first.name
                else
                  "#{@elbs.size} load balancers total"
                end

    @severities = {
      critical: false,
      warning:  false
    }

    @elbs.each { |elb| check_sum_requests elb }

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
