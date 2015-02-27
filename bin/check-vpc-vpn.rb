#! /usr/bin/env ruby
#
# check-vpc-vpn
#
# DESCRIPTION:
#   Check VPN connections to AWS via EC2 API
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
#   Check if VPN connection vpn-00000001 in us-west-2 tunnels are up/down and set error level to warning
#   check-vpc-cpn -r us-west-2 -c vpn-00000001 -w true
#
#   Check if VPN connection vpn-00000001 in us-west-2 tunnels are up/down and set error level to critical
#   check-vpc-cpn -r us-west-2 -c vpn-00000001 -w false
#   check-vpc-cpn -r us-west-2 -c vpn-00000001 
#
# NOTES:
#   YELLOW
#
# LICENSE:
#   Copyright 2014 github.com/bkett
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk-v1'
require 'sensu-pulgins-aws/helpers'

class VPNStatus < Sensu::Plugin::Check::CLI
  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (such as eu-west-1).',
         required: true

  option :vpn_connection_id,
         short: '-c ID',
         long: '--vpn-connection-id ID',
         description: 'AWS VPN Connection object id',
         required: true

  option :warning,
         short: '-w BOOLEAN',
         long: '--warning BOOLEAN',
         description: 'set sensu level for dead tunnels to be warning',
         default: false

  def run
    tunnels_down = false
    vpn_conn = Helpers::VPN.new(config[:aws_region], config[:vpn_connection_id]).connection
    @message = "#{config[:vpn_connection_id]}: "
    vpn_conn.vgw_telemetry.each do |tunnel|
      if tunnel.status != :up
        @message += "[tunnel: #{tunnel.outside_ip_address} #{tunnel.status.upcase}]"
        tunnels_down = true
      end
    end
    if tunnels_down
      if config[:warning]
        warning @message
      else
        critical @message
      end
    else
      ok @message
    end
  end
end
