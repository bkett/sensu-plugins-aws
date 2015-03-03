#!/usr/bin/env ruby
#
# check-elb-health-sdk
# Last Update: 1/22/2015 by bkett
# ===
#
# DESCRIPTION:
#   This plugin checks the health of an Amazon Elastic Load Balancer or all ELBs in a given region.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk-v1
#   gem: uri
#   gem: net/http
#   gem: sensu-plugin
#
# Copyright (c) 2015, Benjamin Kett <bkett@umn.edu>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'sensu-plugin/check/cli'
require 'net/http'
require 'uri'
require 'aws-sdk-v1'
require 'sensu-plugins-aws/helpers'

class ELBHealth < Sensu::Plugin::Check::CLI
  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (such as eu-west-1).',
         default: 'us-east-1'

  option :elb_name,
         short: '-n ELB_NAME',
         long: '--elb-name ELB_NAME',
         description: 'The Elastic Load Balancer name of which you want to check the health'

  option :instances,
         short: '-i INSTANCES',
         long: '--instances INSTANCES',
         description: 'Comma separated list of specific instances IDs inside the ELB of which you want to check the health'

  option :verbose,
         short: '-v',
         long: '--verbose',
         description: 'Enable a little bit more verbose reports about instance health',
         boolean: true,
         default: false

  def check_health(elb)
    unhealthy_instances = {}
    if config[:instances]
      instance_health_hash = elb.instances.health(config[:instances])
    else
      instance_health_hash = elb.instances.health
    end
    instance_health_hash.each do |instance_health|
      if instance_health[:state] != 'InService'
        unhealthy_instances[instance_health[:instance].id] = instance_health[:state]
      end
    end
    if unhealthy_instances.empty?
      'OK'
    else
      unhealthy_instances
    end
  end

  def run
    elbs = Helpers::ELB.new(config[:aws_region], config[:elb_name]).elbs
    @message = (elbs.size > 1 ? config[:aws_region] + ': ' : '')
    critical = false
    elbs.each do |elb|
      result = check_health elb
      if result != 'OK'
        @message += "#{elb.name} unhealthy => #{result.map { |id, state| '[' + id + '::' + state + ']' }.join(' ')}. "
        critical = true
      else
        @message += "#{elb.name} => healthy. "
      end
    end
    if critical
      critical @message
    else
      ok @message
    end
  end
end
