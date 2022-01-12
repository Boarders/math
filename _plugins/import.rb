# This code is roughly based on https://github.com/koraktor/jekyll/tree/import-tag

# frozen_string_literal: true

module Jekyll

  # A generator to embed the URL into each document's data object
  class UrlGenerator < Jekyll::Generator
    def generate(site)
      site.documents.each do |doc|
        doc.data['url'] = doc.url
      end
    end
  end

  # A version of `Page` that is meant to be rendered but not written.
  class ImportedNode < Page
    def initialize(site, base, name, superpage:)
      dir = '_nodes'
      super(site, base, dir, name)
      data['slug'] = basename
      data['level'] = (superpage['level'] || 1) + 1
      data['layout'] = 'import'
    end

    def url
      "/nodes/#{basename}.html"
    end

    def write?
      false
    end
  end

  class NodeGraph
    attr_reader :toc, :cotoc

    def initialize(data)
      @data = data
      @toc = @data['toc'] || {}
      @cotoc = @data['cotoc'] || {}
      @referents = @data['referents'] || {}
      install_on data
    end

    def install_on(data)
      data['toc'] = @toc
      data['cotoc'] = @cotoc
      data['referents'] = @referents
    end

    def register_referent(slug, page)
      backlinks = @referents[slug] || []
      @referents[slug] = backlinks
      backlinks.append page unless backlinks.detect { |existing| existing['slug'] == page['slug'] }
    end

    def register_subpage(page, subpage)
      slug = page['slug']
      subslug = subpage['slug']

      toc = @toc[slug] || []
      @toc[slug] = toc

      cotoc = @cotoc[subslug] || []
      @cotoc[subslug] = cotoc

      toc.append subpage unless toc.detect { |existing| existing['slug'] == subslug }
      cotoc.append page unless cotoc.detect { |existing| existing['slug'] == slug }
    end

  end

  class ImportTag < Liquid::Tag
    def initialize(tag_name, slug, tokens)
      super
      @slug = slug.strip
    end

    def render(context)
      registers = context.registers
      site = registers[:site]
      page = registers[:page]

      imported = ImportedNode.new(site, site.source, "#{@slug}.md", superpage: page)
      NodeGraph.new(site.data).register_subpage(page, imported)

      # tracks dependencies like Jekyll::Tags::IncludeTag so --incremental works
      if page&.key?('path')
        path = site.in_source_dir(page['path'])
        dependency = site.in_source_dir(imported.path)
        site.regenerator.add_dependency(path, dependency)
      end

      imported.render(site.layouts, site.site_payload)
      imported.output
    end
  end

  class RefTag < Liquid::Tag
    def initialize(tag_name, slug, tokens)
      super
      @slug = slug.strip
    end

    def render(context)
      registers = context.registers
      site = registers[:site]
      node = site.collections['nodes'].docs.detect { |doc| doc.data['slug'] == @slug }
      NodeGraph.new(site.data).register_referent(@slug, registers[:page])
      "<a href='#{site.baseurl}#{node.url}' class='slug'>[#{@slug}]</a>"
    end
  end

  class GenerateBacklinksTag < Liquid::Tag
    def render(context)
      registers = context.registers
      site = registers[:site]
      page = registers[:page]

      gph = NodeGraph.new site.data
      gph.install_on page
      nil
    end
  end
end

Liquid::Template.register_tag('generate_backlinks', Jekyll::GenerateBacklinksTag)
Liquid::Template.register_tag('import', Jekyll::ImportTag)
Liquid::Template.register_tag('ref', Jekyll::RefTag)
