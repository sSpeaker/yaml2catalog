Puppet::Parser::Functions::newfunction(:yaml2catalog, :arity => 1, :doc => <<-'ENDHEREDOC') do |args|
 Function for declaring resources from yaml file
ENDHEREDOC
  #Load all puppet functions.
  Puppet::Parser::Functions.autoloader.loadall
  
  #Function for replace variables and explore puppet functions
  def s2v(str)
    #Variables
    if str =~ /\$[{]?\w+[}]?/
      str.gsub(/\$[{]?(\w+)[}]?/) do |t|
        str = str.sub(t,lookupvar($1).to_s)
      end
    end
    #Functions
    if str =~ /%[{]?[a-zA-Z0-9!"'\(\)\*\+,-\.\/:;<=>\?@\[\\\]\^_\\|~]+[\}]?/
      str.gsub(/%[{]?([a-zA-Z0-9!"'\(\)\*\+,-\.\/:;<=>\?@\[\\\]\^_\\|~]+)[\}]?/) do |t|
        str = str.sub(t,eval("function_#{$1}").to_s)
      end
    end
    return str
  end

  raise Puppet::ParseError, ("yaml2catalog(): wrong number of arguments (#{args.length}; must be 1)") if args.length > 1

  YAML.load_file(args[0]).each do |type_name, value|
    type_name = type_name.downcase
    type_exported, type_virtual = false
    if type_name.start_with? '@@'
      type_name = type_name[2..-1]
      type_exported = true
    elsif type_name.start_with? '@'
      type_name = type_name[1..-1]
      type_virtual = true
    end
    
    if type_name == 'class'
      type_of_resource = :class
    elsif type_name == 'variables'
      type_of_resource = :variables
    else
      if resource = Puppet::Type.type(type_name.to_sym)
        type_of_resource = :type
      elsif resource = find_definition(type_name.downcase)
        type_of_resource = :define
      else
        raise ArgumentError, "could not create resource of unknown type #{type_name}"
      end
    end
    #Allow global params for resource
    if value['global']
      defaults = value['global']
      value.delete('global')
    else
     defaults= {}
    end

    value.each do |title, params|
      title = s2v(title)

      #Selectors support
      params.each do |k,v|
        if k =~ /^(\w+)\s+\?\s+(\w+)$/
          v = v[lookupvar($2)] || v['default']
          raise ArgumentError, "Where is no correct variable and default value for \"#{k}\" selector" if ! v
          params.delete(k)
          params["#{$1}"] = v
        end
      end

      if type_of_resource != :variables
        if params
          params = Puppet::Util.symbolizehash(defaults.merge(params))
        else
          params = Puppet::Util.symbolizehash(defaults)
        end
        raise 'params should not contain title' if(params[:title])
      end
      case type_of_resource
      when :variables
        params.each do |k,v|
          raise ArgumentError, "variable \"#{k}\" already defined" if lookupvar(k)
          setvar(s2v(k),s2v(v))
        end

      # JJM The only difference between a type and a define is the call to instantiate_resource
      # for a defined type.
      when :type, :define
        p_resource = Puppet::Parser::Resource.new(type_name, title, :scope => self, :source => resource)
        p_resource.virtual = type_virtual
        p_resource.exported = type_exported
        {:name => title}.merge(params).each do |k,v|
          p_resource.set_parameter(s2v(k),s2v(v))
        end
        if type_of_resource == :define then
          resource.instantiate_resource(self, p_resource)
        end
        compiler.add_resource(self, p_resource)

      when :class
        klass = find_hostclass(title)
        raise ArgumentError, "could not find hostclass #{title}" unless klass
        klass.ensure_in_catalog(self, params)
        compiler.catalog.add_class(title)
      end
    end
  end
end
