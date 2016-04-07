require 'aws-sdk'
require 'digest/md5'

module Jekyll
  module Commands
    class Deploy < Command
      class << self
        def init_with_program(prog)
          prog.command(:deploy) do |c|
            c.syntax 'deploy [--deploy_to=DEPLOY_TO] [--aws_access_key_id=KEY --aws_secret_access_key=SECRET --aws_region=REGION]'
            c.description 'Deploy the site to the remote destination.'

            add_build_options(c)
            
            c.option 'deploy_to', '--deploy_to DEPLOY_TO', String, 'Deploy to a particular configuration'
            c.option 'aws_access_key_id' '--aws_access_key_id ACCESS_KEY_ID', String, 'Use the provided AWS access key id for S3 deployment'
            c.option 'aws_secret_access_key' '--aws_secret_access_key SECRET_ACCESS_KEY', String, 'Use the provided AWS secret access key for S3 deployment'
            c.option 'aws_region' '--aws_region REGION', String, 'Use the provided AWS region for S3 deployment'
            
            c.action do |_, options|
              Jekyll::Commands::Build.process(options)
              Jekyll::Commands::Deploy.process(options)
            end
          end
          
        end
        
        def process(options)
          options = configuration_from_options(options)          
          
          deploy_bits = options['deploy_to'].split('://');
                    
          case deploy_bits[0].downcase
          when 's3'
            s3_deployment(deploy_bits, options)
          else
            Jekyll.logger.error("Unknown deployment location '" + options['deploy_to'] + "'")
            exit(1)
          end
        end
        
        def s3_deployment(deploy_bits, options)
          # Initialize the S3 Resource
          s3_resource = initializeS3(options)
          
          # Work out the bucket and the prefix from the endpoint
          bucket_bits = deploy_bits[1].split('/')
          bucket_name = bucket_bits.shift
          prefix = bucket_bits.join('/')
          
          # Prepare what changes need to be applied
          local_objects = prepare_local(options['destination'], '')
          object_actions = prepare_actions(s3_resource, bucket_name, prefix, local_objects)
          
          # Do the changes
          deploy_to_s3(s3_resource, bucket_name, options['destination'], object_actions)
        end
        
        def prepare_local(local_base, local_path)
          ret = {}
          Dir.foreach("#{local_base}/#{local_path}") do |fname|
            next if(fname == '.' || fname == '..')
            
            this_path = "#{local_path}/#{fname}"
            full_path = "#{local_base}/#{this_path}"
             
            if File.directory?(full_path)
              ret = ret.merge(prepare_local(local_base, this_path))
            else
              file_md5 = Digest::MD5.hexdigest(File.read(full_path))
              nice_path = (this_path.split('/') - [""]).join('/')
              ret[nice_path] = file_md5
            end
          end
          
          return ret
        end
        
        def prepare_actions(s3_resource, bucket_name, prefix, local_objects)
          actions = {}
          s3_resource.bucket(bucket_name).objects({prefix: prefix}).each do |objectsummary|
            if local_objects.has_key?(objectsummary.key)
              remote_hash = objectsummary.etag.tr('"', '')
              if local_objects[objectsummary.key] == remote_hash
                actions[objectsummary.key] = "no_action"
              end
            else
              actions[objectsummary.key] = "delete"
            end
          end
          local_objects.merge(actions)
        end
        
        def deploy_to_s3(s3_resource, bucket_name, local_root, object_actions)
          bucket = s3_resource.bucket(bucket_name)
          object_actions.each do |path, action|
            case action
            when "delete"
              #Delete it
              puts "Removing #{path} from #{bucket_name}"
              bucket.object(path).delete
            when "no_action"
              #Do nothing
              puts "#{path} is unchanged"              
            else
              #Update boiii!
              puts "Pushing #{path} to #{bucket_name}"
              File.open("#{local_root}/#{path}", 'rb') do |file|
                bucket.put_object({
                  acl: "public-read",
                  body: file,
                  key: path
                })
              end
              
            end
          end
        end
        
        def initializeS3(options)
          
          if(!!options['aws_access_key_id'] && !!options['aws_secret_access_key'] && !!options['aws_region'])
            # There is some credentials in the yaml file
            Aws::S3::Resource.new(
              access_key_id: options['aws_access_key_id'],
              secret_access_key: options['aws_secret_access_key'],
              region: options['aws_region']
            )
          elsif !!options['aws']
            # There is some credentials in the yaml file
            Aws::S3::Resource.new(
              access_key_id: options['aws']['access_key_id'],
              secret_access_key: options['aws']['secret_access_key'],
              region: options['aws']['region']
            )
          elsif File.exist?('_secrets/aws.yml')
            config = SafeYAML.load_file('_secrets/aws.yml')
            # There is a aws credentials file specific to this site
            Aws::S3::Resource.new(
              access_key_id: config['access_key_id'],
              secret_access_key: config['secret_access_key'],
              region: config['region']
            )
          elsif File.exist?(File::expand_path('~/.aws/credentials'))
            # There is shared aws credentials
            Aws::S3::Resource.new({region: options['aws_region']})
          else
            # There is no aws credentials
            Jekyll.logger.error("There is no known AWS credentials for S3 deployment!")
            exit(1)
          end
        end
        
      end
    end
  end
end