require 'volt/templates/base_binding'
require 'volt/templates/template_renderer'

class TemplateBinding < BaseBinding
  def initialize(target, context, binding_name, binding_in_path, getter)
    # puts "New template binding: #{context.inspect} - #{binding_name.inspect} - #{getter.inspect}"
    super(target, context, binding_name)
    
    # Binding in path is the path for the template this binding is in
    setup_path(binding_in_path)

    @current_template = nil
    
    # puts "GETTER: #{value_from_getter(getter).inspect}"

    # Find the source for the getter binding
    @path, section = value_from_getter(getter)
    
    if section.is_a?(String)
      # Render this as a section
      @section = section
    else
      # Use the value passed in as the default model
      @model = section
    end

    # Run the initial render
    update

    @path_changed_listener = @path.on('changed') { update } if @path.reactive?
    @section_changed_listener = @section.on('changed') { update } if @section && @section.reactive?
  end
  
  def setup_path(binding_in_path)
    path_parts = binding_in_path.split('/')
    @collection_name = path_parts[0]
    @controller_name = path_parts[1]
    @page_name = path_parts[2]
  end
  
  # Returns true if there is a template at the path
  def check_for_template?(path)
    $page.templates[path]
  end
  
  # Takes in a lookup path and returns the full path for the matching
  # template.  Also returns the controller name if applicable.
  #
  # Looking up a path is fairly simple.  There are 4 parts needed to find
  # the html to be rendered.  File paths look like this:
  # app/{component}/views/{controller_name}/{view}.html
  # Within the html file may be one or more sections.
  # 1. component (app/{comp})
  # 2. controller
  # 3. view
  # 4. sections
  #
  # When searching for a file, the lookup starts at the section, and moves up.
  # when moving up, default values are provided for the section, then view/section, etc..
  # until a file is either found or the component level is reached.
  #
  # The defaults are as follows:
  # 1. component - home
  # 2. controller - index
  # 3. view - index
  # 4. section - body
  def path_for_template(lookup_path, force_section=nil)
    parts = lookup_path.split('/')
    parts_size = parts.size

    default_parts = ['home', 'index', 'index', 'body']

    # When forcing a sub template, we can default the sub template section
    default_parts[-1] = force_section if force_section
    
    (5 - parts_size).times do |path_position|
      # If they passed in a force_section, we can skip the first
      next if force_section && path_position == 0
      
      full_path = [@collection_name, @controller_name, @page_name, nil]

      offset = 0
      start_at = full_path.size - parts_size - path_position
    
      full_path.size.times do |index|
        if index >= start_at
          if part = parts[index-start_at]
            full_path[index] = part
          else
            full_path[index] = default_parts[index]
          end
        end
      end

      path = full_path.join('/')
      if check_for_template?(path)
        controller = nil
        if path_position > 1
          # Lookup the controller
          controller = [full_path[0], full_path[1]]
        end
        return path, controller
      end
    end
    
    return nil, nil
  end

  def update
    full_path, controller = path_for_template(@path.cur, @section.cur)

    @current_template.remove if @current_template
    
    current_context = @context
    
    if @model
      # Load in any procs
      @model.each_pair do |key,value|
        if value.class == Proc
          @model[key] = value.call
        end
      end
    end
    
    # TODO: at the moment a :body section and a :title will both initialize different
    # controllers.  Maybe we should have a way to tie them together?
    if controller
      args = []
      args << SubContext.new(@model) if @model
      
      name = controller[1].camelize
      
      # For the home object, we do not need to namespace our controller
      if controller[0] != 'home'
        base_name = controller[0].camelize
        base_object = Object.send(:const_get, base_name.to_sym)
      else
        base_object = Object
      end
      
      # Initialize the new controller
      current_context = base_object.send(:const_get, (name + 'Controller').to_sym).new(*args)
    elsif @model
      # Passed in attributes, but there is no controller
      current_context = SubContext.new(@model, current_context)      
    end

    @current_template = TemplateRenderer.new(@target, current_context, @binding_name, full_path)
  end

  def remove
    if @path_changed_listener
      @path_changed_listener.remove
      @path_changed_listener = nil
    end

    if @section_changed_listener
      @section_changed_listener.remove
      @section_changed_listener = nil
    end
    
    if @current_template
      # Remove the template if one has been rendered, when the template binding is
      # removed.
      @current_template.remove
    end

    super
  end
end
