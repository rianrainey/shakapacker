require "rgl/adjacency"
require "rgl/topsort"

module Webpacker::Helper
  # Returns the current Webpacker instance.
  # Could be overridden to use multiple Webpacker
  # configurations within the same app (e.g. with engines).
  def current_webpacker_instance
    Webpacker.instance
  end

  # Computes the relative path for a given Webpacker asset.
  # Returns the relative path using manifest.json and passes it to path_to_asset helper.
  # This will use path_to_asset internally, so most of their behaviors will be the same.
  #
  # Example:
  #
  #   <%= asset_pack_path 'calendar.css' %> # => "/packs/calendar-1016838bab065ae1e122.css"
  def asset_pack_path(name, **options)
    path_to_asset(current_webpacker_instance.manifest.lookup!(name), options)
  end

  # Computes the absolute path for a given Webpacker asset.
  # Returns the absolute path using manifest.json and passes it to url_to_asset helper.
  # This will use url_to_asset internally, so most of their behaviors will be the same.
  #
  # Example:
  #
  #   <%= asset_pack_url 'calendar.css' %> # => "http://example.com/packs/calendar-1016838bab065ae1e122.css"
  def asset_pack_url(name, **options)
    url_to_asset(current_webpacker_instance.manifest.lookup!(name), options)
  end

  # Computes the relative path for a given Webpacker image with the same automated processing as image_pack_tag.
  # Returns the relative path using manifest.json and passes it to path_to_asset helper.
  # This will use path_to_asset internally, so most of their behaviors will be the same.
  def image_pack_path(name, **options)
    resolve_path_to_image(name, **options)
  end

  # Computes the absolute path for a given Webpacker image with the same automated
  # processing as image_pack_tag. Returns the relative path using manifest.json
  # and passes it to path_to_asset helper. This will use path_to_asset internally,
  # so most of their behaviors will be the same.
  def image_pack_url(name, **options)
    resolve_path_to_image(name, **options.merge(protocol: :request))
  end

  # Creates an image tag that references the named pack file.
  #
  # Example:
  #
  #  <%= image_pack_tag 'application.png', size: '16x10', alt: 'Edit Entry' %>
  #  <img alt='Edit Entry' src='/packs/application-k344a6d59eef8632c9d1.png' width='16' height='10' />
  #
  #  <%= image_pack_tag 'picture.png', srcset: { 'picture-2x.png' => '2x' } %>
  #  <img srcset= "/packs/picture-2x-7cca48e6cae66ec07b8e.png 2x" src="/packs/picture-c38deda30895059837cf.png" >
  def image_pack_tag(name, **options)
    if options[:srcset] && !options[:srcset].is_a?(String)
      options[:srcset] = options[:srcset].map do |src_name, size|
        "#{resolve_path_to_image(src_name)} #{size}"
      end.join(", ")
    end

    image_tag(resolve_path_to_image(name), options)
  end

  # Creates a link tag for a favicon that references the named pack file.
  #
  # Example:
  #
  #  <%= favicon_pack_tag 'mb-icon.png', rel: 'apple-touch-icon', type: 'image/png' %>
  #  <link href="/packs/mb-icon-k344a6d59eef8632c9d1.png" rel="apple-touch-icon" type="image/png" />
  def favicon_pack_tag(name, **options)
    favicon_link_tag(resolve_path_to_image(name), options)
  end

  # Creates script tags that reference the js chunks from entrypoints when using split chunks API,
  # as compiled by webpack per the entries list in package/environments/base.js.
  # By default, this list is auto-generated to match everything in
  # app/packs/entrypoints/*.js and all the dependent chunks. In production mode, the digested reference is automatically looked up.
  # See: https://webpack.js.org/plugins/split-chunks-plugin/
  #
  # Example:
  #
  #   <%= javascript_pack_tag 'calendar', 'map', 'data-turbolinks-track': 'reload' %> # =>
  #   <script src="/packs/vendor-16838bab065ae1e314.chunk.js" data-turbolinks-track="reload" defer="true"></script>
  #   <script src="/packs/calendar~runtime-16838bab065ae1e314.chunk.js" data-turbolinks-track="reload" defer="true"></script>
  #   <script src="/packs/calendar-1016838bab065ae1e314.chunk.js" data-turbolinks-track="reload" defer="true"></script>
  #   <script src="/packs/map~runtime-16838bab065ae1e314.chunk.js" data-turbolinks-track="reload" defer="true"></script>
  #   <script src="/packs/map-16838bab065ae1e314.chunk.js" data-turbolinks-track="reload" defer="true"></script>
  #
  # DO:
  #
  #   <%= javascript_pack_tag 'calendar', 'map' %>
  #
  # DON'T:
  #
  #   <%= javascript_pack_tag 'calendar' %>
  #   <%= javascript_pack_tag 'map' %>
  def javascript_pack_tag(*names, defer: true, **options)
    if @javascript_pack_tag_loaded
      raise "To prevent duplicated chunks on the page, you should call javascript_pack_tag only once on the page. " \
      "Please refer to https://github.com/shakacode/shakapacker/blob/master/README.md#view-helpers-javascript_pack_tag-and-stylesheet_pack_tag for the usage guide"
    end

    append_javascript_pack_tag(*names, defer: defer)
    non_deferred = sources_from_manifest_entrypoints(javascript_pack_tag_queue[:non_deferred], type: :javascript)
    deferred = sources_from_manifest_entrypoints(javascript_pack_tag_queue[:deferred], type: :javascript) - non_deferred

    @javascript_pack_tag_loaded = true

    capture do
      concat javascript_include_tag(*deferred, **options.tap { |o| o[:defer] = true })
      concat "\n" if non_deferred.any? && deferred.any?
      concat javascript_include_tag(*non_deferred, **options.tap { |o| o[:defer] = false })
    end
  end

  # Creates a link tag, for preloading, that references a given Webpacker asset.
  # In production mode, the digested reference is automatically looked up.
  # See: https://developer.mozilla.org/en-US/docs/Web/HTML/Preloading_content
  #
  # Example:
  #
  #   <%= preload_pack_asset 'fonts/fa-regular-400.woff2' %> # =>
  #   <link rel="preload" href="/packs/fonts/fa-regular-400-944fb546bd7018b07190a32244f67dc9.woff2" as="font" type="font/woff2" crossorigin="anonymous">
  def preload_pack_asset(name, **options)
    if self.class.method_defined?(:preload_link_tag)
      preload_link_tag(current_webpacker_instance.manifest.lookup!(name), options)
    else
      raise "You need Rails >= 5.2 to use this tag."
    end
  end

  # Creates link tags that reference the css chunks from entrypoints when using split chunks API,
  # as compiled by webpack per the entries list in package/environments/base.js.
  # By default, this list is auto-generated to match everything in
  # app/packs/entrypoints/*.js and all the dependent chunks. In production mode, the digested reference is automatically looked up.
  # See: https://webpack.js.org/plugins/split-chunks-plugin/
  #
  # Examples:
  #
  #   <%= stylesheet_pack_tag 'calendar', 'map' %> # =>
  #   <link rel="stylesheet" media="screen" href="/packs/3-8c7ce31a.chunk.css" />
  #   <link rel="stylesheet" media="screen" href="/packs/calendar-8c7ce31a.chunk.css" />
  #   <link rel="stylesheet" media="screen" href="/packs/map-8c7ce31a.chunk.css" />
  #
  #   When using the webpack-dev-server, CSS is inlined so HMR can be turned on for CSS,
  #   including CSS modules
  #   <%= stylesheet_pack_tag 'calendar', 'map' %> # => nil
  #
  # DO:
  #
  #   <%= stylesheet_pack_tag 'calendar', 'map' %>
  #
  # DON'T:
  #
  #   <%= stylesheet_pack_tag 'calendar' %>
  #   <%= stylesheet_pack_tag 'map' %>
  def stylesheet_pack_tag(*names, **options)
    return "" if Webpacker.inlining_css?

    requested_packs = sources_from_manifest_entrypoints(names, type: :stylesheet)
    appended_packs = available_sources_from_manifest_entrypoints(@stylesheet_pack_tag_queue || [], type: :stylesheet)

    @stylesheet_pack_tag_loaded = true

    stylesheet_link_tag(*(requested_packs | appended_packs), **options)
  end

  def append_stylesheet_pack_tag(*names)
    if @stylesheet_pack_tag_loaded
      raise "You can only call append_stylesheet_pack_tag before stylesheet_pack_tag helper. " \
      "Please refer to https://github.com/shakacode/shakapacker/blob/master/README.md#view-helper-append_javascript_pack_tag-and-append_stylesheet_pack_tag for the usage guide"
    end

    @stylesheet_pack_tag_queue ||= []
    @stylesheet_pack_tag_queue |= names

    # prevent rendering Array#to_s representation when used with <%= … %> syntax
    nil
  end

  def append_javascript_pack_tag(*names, defer: true)
    if @javascript_pack_tag_loaded
      raise "You can only call append_javascript_pack_tag before javascript_pack_tag helper. " \
      "Please refer to https://github.com/shakacode/shakapacker/blob/master/README.md#view-helper-append_javascript_pack_tag-and-append_stylesheet_pack_tag for the usage guide"
    end

    hash_key = defer ? :deferred : :non_deferred
    javascript_pack_tag_queue[hash_key] |= names

    # prevent rendering Array#to_s representation when used with <%= … %> syntax
    nil
  end

  private

    def javascript_pack_tag_queue
      @javascript_pack_tag_queue ||= {
        deferred: [],
        non_deferred: []
      }
    end

    def sources_from_manifest_entrypoints(names, type:)
      return sources_from_manifest_entrypoints_in_topological_order(names, type: type) if use_topological_order?

      sources_from_manifest_entrypoints_in_non_topological_order(names, type: type)
    end

    def available_sources_from_manifest_entrypoints(names, type:)
      return available_sources_from_manifest_entrypoints_in_topological_order(names, type: type) if use_topological_order?

      available_sources_from_manifest_entrypoints_in_non_topological_order(names, type: type)
    end

    def sources_from_manifest_entrypoints_in_non_topological_order(names, type:)
      names.map { |name| current_webpacker_instance.manifest.lookup_pack_with_chunks!(name.to_s, type: type) }.flatten.uniq
    end

    def available_sources_from_manifest_entrypoints_in_non_topological_order(names, type:)
      names.map { |name| current_webpacker_instance.manifest.lookup_pack_with_chunks(name.to_s, type: type) }.flatten.compact.uniq
    end

    def sources_from_manifest_entrypoints_in_topological_order(names, type:)
      graph = RGL::DirectedAdjacencyGraph.new

      names.each { |name|
        packs = current_webpacker_instance.manifest.lookup_pack_with_chunks!(name.to_s, type: type)
        add_packs_to_directed_graph(packs, graph)
      }

      graph.topsort_iterator.to_a.compact
    end

    def available_sources_from_manifest_entrypoints_in_topological_order(names, type:)
      graph = RGL::DirectedAdjacencyGraph.new

      names.each { |name|
       packs = current_webpacker_instance.manifest.lookup_pack_with_chunks(name.to_s, type: type)
       add_packs_to_directed_graph(packs, graph)  if packs.present?
     }

      graph.topsort_iterator.to_a.compact
    end

    def add_packs_to_directed_graph(packs, graph)
      packs.each_index { |index|
        return unless index < packs.size
        v1 = packs[index]
        v2 = packs[index + 1]
        graph.add_edge(v1, v2)
      }
    end

    def resolve_path_to_image(name, **options)
      path = name.starts_with?("static/") ? name : "static/#{name}"
      path_to_asset(current_webpacker_instance.manifest.lookup!(path), options)
    rescue
      path_to_asset(current_webpacker_instance.manifest.lookup!(name), options)
    end

    def use_topological_order?
      current_webpacker_instance.config.use_topological_order?
    end
end
