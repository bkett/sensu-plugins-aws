require 'aws-sdk-v1'

module Helpers

  def aws_config aws_region
    aws_access_key = ENV['AWS_ACCESS_KEY_ID']
    aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']

    hash = {}
    hash.update access_key_id: aws_access_key, secret_access_key: aws_secret_access_key if aws_access_key && aws_secret_access_key
    hash.update region: aws_region
    hash
  end

  class Config
    def initialize region
      @region = region
    end

    def sel! arr, sub_arr=nil
      arr.select! { |obj| sub_arr.include? obj.name } if sub_arr
    end

  end

  class EC2 < Config
    include Helpers

    def initialize region
      super region
    end

    def ec2
      @ec2 ||= AWS::EC2.new(aws_config @region)
    end

    def client
      @client ||= AWS::EC2::Client.new(aws_config @region)
    end

  end


  class ELB < Config
    include Helpers

    def initialize region, elb_names=nil
      super region
      @elb_names = elb_names if elb_names
    end

    def elb
      @elb ||= AWS::ELB.new(aws_config @region)
    end

    def elbs
      return @elbs if @elbs
      @elbs = elb.load_balancers.to_a
      sel! @elbs, @elb_names
      @elbs
    end

  end

  class DynamoDB < Config
    include Helpers

    def initialize region, table_names
      super region
      @table_names = table_names
    end

    def dynamo_db
      @dynamo_db ||= AWS::DynamoDB.new(aws_config @region)
    end

    def tables
      return @tables if @tables
      @tables = dynamo_db.tables.to_a
      sel! @tables, @table_names
      @tables
    end

  end

  class RDS < Config
    include Helpers

    def initialize region
      super region
    end

    def client
      @client ||= AWS::RDS::Client.new(aws_config @region)
    end

    def rds
      @rds ||= AWS::RDS.new(aws_config @region)
    end

  end

  class Redshift < Config
    include Helpers

    def initialize region
      super region
    end

    def client
      @client ||= AWS::Redshift::Client.new(aws_config @region)
    end

    def get_relevant_clusters instances
      return @clusters if @clusters
      @clusters = client.describe_clusters[:clusters].map { |c| c[:cluster_identifier] }
      sel! @clusters, instances
      @clusters
    end

  end

  class VPN < EC2
    include Helpers

    def initialize region, vpn_connection_id
      super region
      @vpn_conn_id = vpn_connection_id
    end

    def connection 
      @conn ||= ec2.vpn_connections[@vpn_conn_id]
    end

  end

  class CloudWatch < Config
    include Helpers
    
    def initialize opts, metric_opts, unit
      super opts[:region]
      @stat_opts = opts
      @metric_opts = metric_opts
      @unit = unit
    end

    private
    def statistics_options
      {
        start_time: @stat_opts[:end_time] - @stat_opts[:period].to_i * 5,
        end_time:   @stat_opts[:end_time],
        statistics: [@stat_opts[:statistics].to_s.capitalize],
        period:     @stat_opts[:period],
        unit:       @unit
      }
    end

    def generate_metric aws_namespace, metric_opts=@metric_opts 
      cloud_watch.metrics.with_namespace(aws_namespace).with_metric_name(metric_opts[:name]).with_dimensions( \
                            name: metric_opts[:dimension_name], value: metric_opts[:aws_obj_name]).first
    end

    def get_latest_value 
        opts = statistics_options
      begin
        @metric.statistics(opts).datapoints.sort_by { |datapoint| datapoint[:timestamp] }.last[@stat_opts[:statistics]]
      rescue
        -1
      end
    end

    def cloud_watch
      @cloud_watch ||= AWS::CloudWatch.new(aws_config @region)
    end

  end

  class DynamoWatch < CloudWatch
    
    def initialize opts, metric_opts, unit
      super
      @aws_namespace = 'AWS/DynamoDB'
    end

    def get_latest_value
      @metric = generate_metric @aws_namespace
      super
    end
  end

  class EC2Watch < CloudWatch

    def initialize opts, metric_opts, unit
      super
      @aws_namespace = 'AWS/EC2'
    end

    def get_latest_value 
      @metric = generate_metric @aws_namespace
      super
    end
      
  end
  
  class ELBWatch < CloudWatch

    def initialize opts, metric_opts, unit
      super
      @aws_namespace = 'AWS/ELB'
    end

    def get_latest_value
      @metric = generate_metric @aws_namespace
      super
    end

  end

  class RDSWatch < CloudWatch

    def initialize opts, metric_opts, unit
      super
      @aws_namespace = 'AWS/RDS'
    end

    def get_latest_value
      @metric = generate_metric @aws_namespace
      super
    end

  end

end
