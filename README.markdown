# [Jekyll](https://jekyllrb.com/)

This is a fork of the main [Jekyll project](https://github.com/jekyll/jekyll), with the added feature
to build and deploy to Amazon S3 with a single command.

Jekyll is a simple, blog-aware, static site generator perfect for personal, project, or organization sites. Think of it like a file-based CMS, without all the complexity. Jekyll takes your content, renders Markdown and Liquid templates, and spits out a complete, static website ready to be served by Apache, Nginx or another web server. Jekyll is the engine behind [GitHub Pages](https://pages.github.com), which you can use to host sites right from your GitHub repositories.

## Installation

Installation follows the same instructions as installing a [development version](https://jekyllrb.com/docs/installation/#pre-releases) of Jekyll.

```bash
$ git clone git://github.com/yayandyc/jekyll.git
$ cd jekyll
$ script/bootstrap
$ bundle exec rake build
$ ls pkg/*.gem | head -n 1 | xargs gem install -l
```

## Usage

Using this version of Jekyll is identical to using the standard Jekyll, with the additional command `jekyll deploy`, which does the deployment.

## Configuration

In order to tell Jekyll where to deploy to, you will need to add some configuration to the `_config.yml` file of the site.

```yaml
# S3 Deployment settings
deploy_to: 's3://<bucket>[/<prefix>]'
```

### AWS Configuration

In order to push objects to AWS, you will need to configure credentials to use for AWS. There are several options as to where you can store these credentials.

#### Shared AWS Credentials

This is the approach to storing AWS credentials that is recommended by Amazon. It requires you to store the access key and secret in your user home directory under `~/.aws/credentials`.

Using this method, you are required to add `region: 'your-region'` to the `_config.yml` configuration.

See the [AWS Ruby docs](http://docs.aws.amazon.com/sdk-for-ruby/latest/DeveloperGuide/aws-ruby-sdk-getting-started.html#aws-ruby-sdk-credentials-shared) for more information on setting these credentials.

#### Separate site credentials (recommended)

This method is recommended as it stores the credentials in a separate file and can still be specific to the site.

* Create a new directory in the site's root directory `_aws`
* Add `_aws` to your `.gitignore` file (recommended)
* In this directory, add a new file `_aws/credentials.yml`
* Populate the file with the AWS credentials and the region to use
```yaml
access_key_id: 'your_access_key_id'
secret_access_key: 'your_secret_access_key'
region: 'your_region'
```

#### Site configured credentials

This method is very similar to the above, but it relies on storing the credentials with the rest of
the site configurations. While this makes some sense, it is not a great idea if your _config.yml file
is under version control (especially if you have a public github repository).

Add the AWS credentials and region to the `_config.yml` file:
```yaml
access_key_id: 'your_access_key_id'
secret_access_key: 'your_secret_access_key'
region: 'your_region'
```

## License

See the [LICENSE](https://github.com/yayandyc/jekyll/blob/master/LICENSE) file.
