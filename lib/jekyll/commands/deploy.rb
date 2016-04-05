require 'aws-sdk'
require 'digest/md5'

module Jekyll
  module Commands
    class Deploy < Command
      class << self
        def init_with_program(prog)
          prog.command(:deploy) do |c|
            c.syntax 'deploy [options]'
            c.description 'Deploy the site to the remote destination.'

            add_build_options(c)
            
            c.option 'deploy_to', '--deploy_to DEPLOY_TO', String, 'Deploy to a particular configuration'

            c.action do |_, options|
              #Jekyll::Commands::Build.process(options)
              Jekyll::Commands::Deploy.process(options)
            end
          end
          
        end
        
        def process(options)
          options = configuration_from_options(options)          
          Jekyll::Commands::Build.process(options)
          
          deploy_bits = options['deploy_to'].split('://');
                    
          case deploy_bits[0].downcase
          when 's3'
            s3_resource = initializeS3(options)
            
            bucket_bits = deploy_bits[1].split('/')
            bucket_name = bucket_bits.shift
            prefix = bucket_bits.join('/')
            
            local_objects = prepare_local(options['destination'], '')
            
            object_actions = prepare_actions(s3_resource, bucket_name, prefix, local_objects)
            
            deploy_to_s3(s3_resource, bucket_name, options['destination'], object_actions)
            
          else
            Jekyll.logger.error("Unknown deployment location '" + options['deploy_to'] + "'")
            exit(1)
          end
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
              if local_objects[objectsummary.key] == s3_resource.client.head_object({bucket: bucket_name, key: objectsummary.key}).metadata['object_hash']
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
                  key: path,
                  metadata: {object_hash: action}
                })
              end
              
            end
          end
        end
        
        def initializeS3(options)
          if !!options['aws']
            # There is some credentials in the yaml file
            Aws::S3::Resource.new(
              access_key_id: options['aws']['access_key_id'],
              secret_access_key: options['aws']['secret_access_key'],
              region: options['aws']['region']
            )
          elsif File.exist?('_aws/credentials.yml')
            config = SafeYAML.load_file('_aws/credentials.yml')
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
        
        def deploy_to_aws_s3(dest, s3_client, bucket, prefix)
          
          Dir.foreach(dest) do |fname|
            next if fname == '.' || fname == '..'
            
            next_object = prefix.empty? ? fname : [prefix, fname].join('/')
            disk_path = "#{dest}/#{fname}"
             
            if File.directory?(disk_path)
              deploy_to_aws_s3(disk_path, s3_client, bucket, next_object)
            else
              do_object(disk_path, next_object, s3_client, bucket)
            end
          end
        end
        
#        def get_bucket_objects(bucket_name, prefix, s3_client)
#          config = s3_client.config
#          bucket = Aws::S3::Resource.new(
#            access_key_id: config['access_key_id'],
#            secret_access_key: config['secret_access_key'],
#            region: config['region'])
#          ret = Array.new
#          
#          bucket.objects({prefix: prefix}).each do |obj|
#            ret.push(obj.key)
#            #puts "  #{obj.key} => #{obj.etag}"
#          end
#          ret
#        end
        
        def do_object(disk_path, object_path, s3_client, bucket)      
          file_md5 = Digest::MD5.hexdigest(File.read(disk_path))
          push_required = true
          
          print "#{bucket}::#{object_path} - "
          
          s3_client.bucket(bucket).objects.each do |objectsummary|
            if(objectsummary.key == object_path)
              puts " --- " + objectsummary.key
            end
          end
          
#          s3_client.bucket(bucket).objects.each do |objectsummary|
#            if(objectsummary.key == object_path)
#              resp = s3_client.head_object({
#                bucket: bucket,
#                key: "#{object_path}"
#              })
#              
#              if !!resp.metadata['object_hash']
#                push_required = resp.metadata['object_hash'] != file_md5
#              end
#            end
#          end
#             
#          if push_required
#            puts "Deploying new file."
#            File.open(disk_path, 'rb') do |file|
#              s3_client.put_object(bucket: bucket, key: object_path.split('/').join('/'), body: file,
#              metadata: {object_hash: file_md5})
#            end
#          else
#            puts "No change"
#          end
          
          
        end
      end
    end
  end
end