require 'aws-sdk'
require 'digest/md5'
require 'filemagic'

module Jekyll
  module Commands
    class Deploy < Command
      class << self
        
        def init_with_program(prog)
          prog.command(:deploy) do |c|
            c.syntax 'deploy [--force_deploy] [--deploy_to=DEPLOY_TO] [--aws_access_key_id=KEY --aws_secret_access_key=SECRET --aws_region=REGION]'
            c.description 'Deploy the site to the remote destination.'

            add_build_options(c)
            
            c.option 'deploy_to', '--deploy_to DEPLOY_TO', String, 'Deploy to a particular configuration'
            c.option 'aws_access_key_id', '--aws_access_key_id ACCESS_KEY_ID', String, 'Use the provided AWS access key id for S3 deployment'
            c.option 'aws_secret_access_key', '--aws_secret_access_key SECRET_ACCESS_KEY', String, 'Use the provided AWS secret access key for S3 deployment'
            c.option 'aws_region', '--aws_region REGION', String, 'Use the provided AWS region for S3 deployment'
            c.option 'force_deploy', '--force_deploy', 'Force all objects to be updated'
            c.option 'debug', '--debug', 'Spit lots of output'
                        
            c.action do |_, options|
              Jekyll::Commands::Build.process(options)
              Jekyll::Commands::Deploy.process(options)
            end
          end
          
        end
        
        def process(options)
          
          options = configuration_from_options(options)
          options['force_deploy'] = false unless options.key?('force_deploy')
          
          @all_options = options
          
          puts "Processing with options: " + options.to_s if @all_options['debug']
            
          deploy_bits = options['deploy_to'].split('://');
                    
          case deploy_bits[0].downcase
          when 's3'
            puts "Deploying to S3 - #{options['deploy_to']} " if @all_options['debug']
            s3_deployment(deploy_bits, options)
          else
            Jekyll.logger.error("Unknown deployment location '" + options['deploy_to'] + "'")
            exit(1)
          end
        end
        
        def s3_deployment(deploy_bits, options)
          # Initialize the S3 Resource
          initialize_aws(options)
          puts "Creating new S3 resource" if @all_options['debug']
          s3_resource = Aws::S3::Resource.new
          
          # Work out the bucket and the prefix from the endpoint
          bucket_bits = deploy_bits[1].split('/')
          bucket_name = bucket_bits.shift
          prefix = bucket_bits.join('/')
          
          # Prepare what changes need to be applied
          puts "Preparing local objects" if @all_options['debug']
          local_objects = prepare_local(options['destination'], '')
          puts "Preparing Actions" if @all_options['debug']
          object_actions = prepare_actions(s3_resource, bucket_name, prefix, local_objects, options['force_deploy'])
          
          puts "Actions: " + object_actions.to_s if @all_options['debug']
            
          # Do the changes
          deploy_to_s3(s3_resource, bucket_name, options['destination'], object_actions, options)
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
              puts "#{nice_path}: #{file_md5}" if @all_options['debug']
              ret[nice_path] = file_md5
            end
          end
          
          return ret
        end
        
        def prepare_actions(s3_resource, bucket_name, prefix, local_objects, force_update)
          actions = {}
          s3_resource.bucket(bucket_name).objects({prefix: prefix}).each do |objectsummary|
            if local_objects.has_key?(objectsummary.key)
              remote_hash = objectsummary.etag.tr('"', '')
              if local_objects[objectsummary.key] == remote_hash && !force_update
                actions[objectsummary.key] = "no_action"
              else
                actions[objectsummary.key] = "update"
              end
            else
              actions[objectsummary.key] = "delete"
            end
          end
          local_objects.merge(actions)
        end
        
        def deploy_to_s3(s3_resource, bucket_name, local_root, object_actions, options)
          puts "Deploying" if @all_options['debug']
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
              #Determine the MIME type
              mime_type = naive_mime_type("#{local_root}/#{path}")
              puts "Pushing #{path} to #{bucket_name}"
              File.open("#{local_root}/#{path}", 'rb') do |file|
                bucket.put_object({
                  acl: "public-read",
                  body: file,
                  key: path,
                  content_type: mime_type
                })
              end
            end
          end
          
          puts "Invalidating Cloudfront" if @all_options['debug']
          items_to_update = object_actions.select { |k,v| v == "update" }.keys.map { |k| "/#{k}" }
          invalidate_cloudfront_cache(options, items_to_update) if items_to_update.length > 0
        end
        
        def invalidate_cloudfront_cache(options, items_to_invalidate)
          puts "Invalidating: " + items_to_invalidate.to_s if @all_options['debug']
          if !!options['cloudfront']['region']
            cloudfront = Aws::CloudFront::Client.new(
              region: options['cloudfront']['region']
            )
          else
            cloudfront = Aws::CloudFront::Client.new
          end
          
          cloudfront.create_invalidation({
            distribution_id: options['cloudfront']['distribution_id'], 
            invalidation_batch: { 
              paths: { 
                quantity: items_to_invalidate.length,
                items: items_to_invalidate,
              },
              caller_reference: "utc_" + Time.now.utc.to_i.to_s,
            },
          })
        end
        
        def naive_mime_type(filepath)
          extension = filepath.split('.').pop
          case extension
          when 'html'
            "text/html"
          when 'css'
            "text/css"
          when 'js'
            "application/javascript"
          when 'svg'
            "image/svg+xml"
          when 'png'
            "image/png"
          when 'jpg', 'jpeg'
            "image/jpeg"
          when 'gif'
            "image/gif"
          else
            FileMagic.new(FileMagic::MAGIC_MIME).file(filepath)
          end
        end
        
        def initialize_aws(options)
          puts "Initializing AWS" if @all_options['debug']
          if(!!options['aws_access_key_id'] && !!options['aws_secret_access_key'] && !!options['aws_region'])
            # There is some credentials in the command line
            puts "Credentials on command line" if @all_options['debug']
            Aws.config.update({
              :access_key_id => options['aws_access_key_id'],
              :secret_access_key => options['aws_secret_access_key'],
              :region => options['aws_region']
            })
          elsif !!options['aws']
            puts "Credentials in site config" if @all_options['debug']
            # There is some credentials in the yaml file
            Aws.config.update({
              :access_key_id => options['aws']['access_key_id'],
              :secret_access_key => options['aws']['secret_access_key'],
              :region => options['aws']['region']
            })
          elsif File.exist?('_secrets/aws.yml')
            puts "Credentials in _secrets" if @all_options['debug']
            config = SafeYAML.load_file('_secrets/aws.yml')
            # There is a aws credentials file specific to this site
            Aws.config.update({
              :access_key_id => config['access_key_id'],
              :secret_access_key => config['secret_access_key'],
              :region => config['region']
            })
          elsif File.exist?(File::expand_path('~/.aws/credentials'))
            puts "Credentials are shared" if @all_options['debug']
            # There is shared aws credentials
            Aws.config.update({
              :region => config['region']
            })
          else
            # There is no aws credentials
            Jekyll.logger.error("There is no known AWS credentials for S3 deployment!")
            exit(1)
          end
          puts "AWS initialized" if @all_options['debug']
        end
        
      end
    end
  end
end