require 'aws-sdk'

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

    def sel! arr, name=nil
      arr.select! { |obj| name.include? obj.name } if name
    end

  end


  class ELB < Config
    include Helpers

    def initialize region, elb_name=nil
      super region
      @elb_name = elb_name if elb_name
    end

    def elb
      @elb ||= AWS::ELB.new(aws_config @region)
    end

    def elbs
      return @elbs if @elbs
      @elbs = elb.load_balancers.to_a
      sel! @elbs, @elb_name
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

  class CloudWatch < Config
    include Helpers
    
    def initialize region
      super region

    end

    def cloud_watch
      @cloud_watch ||= AWS::CloudWatch.new(aws_config @region)
    end

    def statistics_options options
      {
        start_time: options[:end_time] - options[:period],
        end_time:   options[:end_time],
        statistics: [options[:statistics].to_s.capitalize],
        period:     options[:period]
      }
    end

    def generate_metric name, aws_obj_name, aws_namespace, dimension_name 
      cloud_watch.metrics.with_namespace(aws_namespace).with_metric_name(name).with_dimensions(name: dimension_name, value: aws_obj_name)
    end

    def get_latest_value metric, config
      begin
        metric.statistics(statistics_options(config).merge unit: 'Count').datapoints.sort_by { |datapoint| datapoint[:timestamp] }.last[config[:statistics]]
      rescue
        0
      end
    end

  end

end
