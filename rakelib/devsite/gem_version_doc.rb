require_relative "repo_metadata"
require_relative "repo_doc_common"

class GemVersionDoc < RepoDocCommon
  def initialize input_dir, output_dir, metadata = nil
    @input_dir = input_dir
    @output_dir = output_dir
    if metadata.nil?
      @metadata = RepoMetadata.from_source "#{input_dir}/.repo-metadata.json"
    else
      @metadata = RepoMetadata.from_source metadata
    end
  end

  def build
    FileUtils.remove_dir @output_dir if Dir.exists? @output_dir
    markup = "--markup markdown --markup-provider redcarpet"

    Dir.chdir @input_dir do
      cmds = ["-o #{@output_dir}", markup]
      cmd "yard --verbose #{cmds.join ' '}"
    end
    @metadata.build @output_dir
    fix_gem_docs
  end

  def build_cloudrad
    FileUtils.remove_dir @output_dir if Dir.exists? @output_dir
    Dir.chdir @input_dir { cmd "rake cloudrad" }
    @metadata.build @output_dir
  end

  def fix_gem_docs
    return unless @input_dir.to_s.include? "google-cloud-trace"

    puts "cd #{@output_dir} [google-cloud-trace fixes]"
    Dir.chdir @output_dir do
      Dir.glob(File.join("**", "*.html")).each do |file_path|
        file_contents = File.read file_path
        file_contents.gsub! "{% dynamic print site_values.console_name %}",
                            "Google Cloud Platform Console"
        file_contents.gsub! "dynamic print site_values.console_name %",
                            "Google Cloud Platform Console"
        File.write file_path, file_contents
      end
    end
  end

  def upload
    Dir.chdir @output_dir do
      opts = [
        "--credentials=#{ENV['KOKORO_KEYSTORE_DIR']}/73713_docuploader_service_account",
        "--staging-bucket=#{ENV.fetch 'STAGING_BUCKET', 'docs-staging'}",
        "--metadata-file=./docs.metadata"
      ]
      cmd "python3 -m docuploader upload . #{opts.join ' '}"
    end
  end

  def upload_cloudrad
    Dir.chdir @output_dir do
      opts = [
        "--credentials=#{ENV['KOKORO_KEYSTORE_DIR']}/73713_docuploader_service_account",
        "--staging-bucket=#{ENV.fetch 'V2_STAGING_BUCKET', 'docs-staging'}",
        "--metadata-file=./docs.metadata"
      ]
      cmd "python3 -m docuploader upload . #{opts.join ' '}"
    end
    python3 -m docuploader upload docs/_build/html/docfx_yaml
      --metadata-file docs.metadata
      --destination-prefix docfx
      --staging-bucket "${}"
  end

  def publish
    build
    upload
  end

  def fix_relative_links
    Dir.chdir @input_dir do
      files = Dir.glob("**/*.md")
      files.each do |file|
        content = File.read file
        content.gsub! %r{\.\./(.*)/(.*).md}, "https://googleapis.dev/ruby/\\1/latest/file.\\2.html"
        content.gsub! %r{\./(.*).md}, "https://googleapis.dev/ruby/#{@input_dir.split('/').last}/latest/file.\\1.html"
        content.gsub! %r{\.\./(.*)\)}, "https://googleapis.dev/ruby/\\1/latest)"
        File.write file, content
      end
    end
  end
end
