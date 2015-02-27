#! /usr/bin/env ruby
#
# check-ec2-network
#
# DESCRIPTION:
#   Check EC2 Network Metrics by CloudWatch API.
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
#   ./check-ec2-network.rb -r ${you_region} -i ${your_instance_id} --warning-over 1000000 --critical-over 1500000
#   ./check-ec2-network.rb -r ${you_region} -i ${your_instance_id} -d NetworkIn --warning-over 1000000 --critical-over 1500000
#   ./check-ec2-network.rb -r ${you_region} -i ${your_instance_id} -d NetworkOut --warning-over 1000000 --critical-over 1500000
#
# NOTES:
#
# LICENSE:
#   Yohei Kawahara <inokara@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require 'sensu-pulgins-aws/helpers'

class CheckEc2Network < Sensu::Plugin::Check::CLI
  option :region,
         short:       '-r R',
         long:        '--region REGION',
         description: 'AWS region'

  option :instance_id,
         short:       '-i instance-id',
         long:        '--instance-id instance-ids',
         description: 'EC2 Instance ID to check.',
         required:    true

  option :end_time,
         short:       '-t T',
         long:        '--end-time TIME',
         default:     Time.now,
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

  option :direction,
         short:       '-d',
         long:        '--direction STRING',
         default:     'NetworkIn',
         description: 'Direction of network traffic to measure. Valid options are NetworkIn or Network Out.'

  %w(warning critical).each do |severity|
    option :"#{severity}_over",
           long:        "--#{severity}-over COUNT",
           description: "Trigger a #{severity} if network traffice is over specified Bytes"
  end

  def run
    metric_conf = {
                    name:           config[:direction],
                    aws_obj_name:   config[:instance_id],
                    dimension_name: 'InstanceId'
                  }
    @ew = Helpers::EC2Watch.new config, metric_conf, 'Bytes'
    network_value = @ew.get_latest_value

    if !network_value.nil? && network_value > config[:critical_over].to_f
      critical "#{config[:direction]} at #{network_value} Bytes"
    elsif !network_value.nil? && network_value > config[:warning_over].to_f
      warning "#{config[:direction]} at #{network_value} Bytes"
    else
      ok "#{config[:direction]} at #{network_value} Bytes"
    end
  end
end
