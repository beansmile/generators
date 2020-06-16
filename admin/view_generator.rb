module Generators::Admin
  class ViewGenerator < Rails::Generators::NamedBase
    RELATION_DISPLAY_COLUMN_NAME = ["name", "title", "label", "nickname", "id"]

    source_root File.expand_path('templates', __dir__)

    def set_i18n
      I18n.locale = :en
    end

    def create_index
      return unless index_api_route

      template("../templates/index.vue.tt", "tmp/#{collection_name}/index.vue")
    end

    def create_show
      return unless show_api_route

      template("../templates/show.vue.tt", "tmp/#{collection_name}/show.vue")
    end

    def create_new
      return unless create_api_route

      template("../templates/new.vue.tt", "tmp/#{collection_name}/new.vue")
    end

    def create_edit
      return unless update_api_route

      template("../templates/edit.vue.tt", "tmp/#{collection_name}/edit.vue")
    end

    def create_route
      template("../templates/route.js.tt", "tmp/#{collection_name}/route.js")
    end

    def create_columns
      template("../templates/columns.js.tt", "tmp/#{collection_name}/columns.js")
    end

    def puts_messages
      puts <<~FILE
      #########################################################################
      文件已生成，已存放到以下目录
      tmp/#{collection_name}

      把下面的内容复制到src/router.js的routes变量里
      require('@/views/#{collection_name}/route').default

      把下面的内容复制到src/constants.js
      FILE

      (filter_data + form_columns_data).select { |data| data[:form_component] == "enum" }.map { |data| data[:attribute] }.uniq.each do |attribute|
        puts "export const #{resource_class.name.underscore.upcase}_#{attribute.pluralize.upcase} = {"
        resource_class.send(attribute.pluralize).keys.each do |key|
          puts "  #{key}: '#{resource_class.human_attribute_name("#{attribute}.#{key}")}',"
        end
        puts "}"
        puts ""
      end
      puts "#########################################################################"
    end

    private
    def resource_class
      @resource_class ||= file_name.classify.constantize
    end

    def namespace_classify
      @namespace_classify ||= "AdminAPI"
    end

    def grape_class
      @grape_class ||= "#{namespace_classify}::API::V1::#{resource_class.name.pluralize}".constantize
    end

    def resource_name
      @resource_name ||= resource_class.name.underscore.singularize
    end

    def collection_name
      @collection_name ||= resource_class.name.underscore.pluralize
    end

    def index_api_route
      @index_api_route ||= grape_class.routes.detect { |route| route.request_method == "GET" && route.path == "/api/:version/#{collection_name}(.json)" }
    end

    def show_api_route
      @show_api_route ||= grape_class.routes.detect { |route| route.request_method == "GET" && route.path == "/api/:version/#{collection_name}/:id(.json)" }
    end

    def create_api_route
      @create_api_route ||= grape_class.routes.detect { |route| route.request_method == "POST" && route.path == "/api/:version/#{collection_name}(.json)" }
    end

    def update_api_route
      @update_api_route ||= grape_class.routes.detect { |route| route.request_method == "PUT" && route.path == "/api/:version/#{collection_name}/:id(.json)" }
    end

    def destroy_api_route
      @destroy_api_route ||= grape_class.routes.detect { |route| route.request_method == "DELETE" && route.path == "/api/:version/#{collection_name}/:id(.json)" }
    end

    def resource_detail_entity
      @resource_detail_entity ||= "#{namespace_classify}::API::Entities::#{resource_class}Detail".constantize
    end

    def filter_data
      return @filter_data if @filter_data

      @filter_data = []

      index_api_route.settings[:description][:params].delete_if { |k, v| k.in?(["page", "per_page", "offset", "order_by"]) }.each do |key, options|
        # TODO 找出更好的方法能处理通过title_cont解释得到title的方法
        condition = resource_class.ransack(key => 1).conditions[0]

        next unless condition

        attribute = condition.attributes[0].name

        next unless column = resource_class.columns.detect { |column| column.name == attribute.to_s }
        attribute_type = column.sql_type_metadata.type

        form_component = if resource_class.defined_enums[attribute]
                           "enum"
                         else
                           case attribute_type
                           when :boolean
                             "select"
                           else
                             "input"
                           end
                         end

        @filter_data << {
          prop: key.to_s,
          attribute: attribute,
          label: resource_class.human_attribute_name(attribute),
          attribute_type: attribute_type,
          render_form: true,
          form_component: form_component,
          type: "filter"
        }
      end


      @filter_data
    end

    def filter_array
      return unless index_api_route

      array = []
      array << "["

      filter_data.each do |data|
        array << add_column(data)
      end

      array << "  ]"

      array.join("\n")
    end

    def index_import
      array = filter_data.select { |data| data[:form_component] == "enum" }

      return if array.blank?

      [
        "import { #{array.map { |data| "#{resource_class.name.underscore.upcase}_#{data[:attribute].pluralize.upcase}" }.join(", ")} } from '@/constants';",
        "import _ from 'lodash';"
      ].join("\n")
    end

    def columns_import
      array = []
      enum_data_array = form_columns_data.select { |data| data[:form_component] == "enum" }

      array << "import { #{enum_data_array.map { |data| "#{resource_class.name.underscore.upcase}_#{data[:attribute].pluralize.upcase}" }.join(", ")} } from '@/constants';" if enum_data_array.any?
      array << "import { permissionService } from 'beans-admin-plugin';" if form_columns_data.any? { |data| data[:form_component] == "belongs_to" }

      array.join("\n")
    end

    def form_columns_data
      return @form_columns_data if @form_columns_data

      @form_columns_data = []

      @form_columns_data << {
        prop: "id",
        attribute: "id",
        label: resource_class.human_attribute_name(:id),
        sort: true,
        width: 80,
        type: "column"
      }

      resource_detail_entity.documentation.each do |attribute, _|
        next if attribute.in?([:id, :created_at, :updated_at])

        # TODO 暂时只处理属于model自身的属性，不处理关联关系
        next unless column = resource_class.columns.detect { |column| column.name == attribute.to_s }

        belongs_to_relations = resource_class.reflect_on_all_associations(:belongs_to).inject({}) { |hash, r| hash[r.foreign_key] = r; hash }

        create_or_update_api_route = create_api_route || update_api_route
        attribute_type = column.sql_type_metadata.type

        form_component, render_cell_component = if attribute == :email
                                                  ["email", nil]
                                                elsif resource_class.defined_enums[attribute.to_s]
                                                  ["enum", "enum"]
                                                elsif belongs_to_relation = belongs_to_relations[attribute.to_s]
                                                  ["belongs_to", "belongs_to"]
                                                elsif attribute.in?([:avatar, :cover, :image, :images])
                                                  ["upload", "image"]
                                                else
                                                  case attribute_type
                                                  when :boolean
                                                    ["switch", "bool"]
                                                  when :datetime
                                                    ["input", "time"]
                                                  when :text
                                                    ["textarea", "textarea"]
                                                  else
                                                    ["input", nil]
                                                  end
                                                end

        render_form = create_or_update_api_route ? create_or_update_api_route.settings[:description][:params].try(:[], attribute.to_s)&.present? : false

        sort = if render_cell_component.in?(["textarea", "image", "belongs_to"])
                 false
               else
                 true
               end

        hide_in_table = if attribute_type == :text
                          true
                        else
                          false
                        end

        @form_columns_data << {
          prop: attribute.to_s,
          attribute: attribute.to_s,
          label: resource_class.human_attribute_name(attribute),
          sort: sort,
          render_form: render_form,
          required: render_form ? create_or_update_api_route.settings[:description][:params][attribute.to_s][:required] : false,
          form_component: form_component,
          hide_in_table: hide_in_table,
          render_cell_component: render_cell_component,
          type: "column",
          belongs_to_relation: belongs_to_relation
        }
      end

      ["created_at", "updated_at"].each do |attribute|
        @form_columns_data << {
          prop: attribute,
          attribute: attribute,
          label: resource_class.human_attribute_name(attribute),
          hide_in_table: true,
          render_cell_component: "time",
          type: "column"
        }
      end

      @form_columns_data
    end

    def columns_array
      array = []
      array << "["


      form_columns_data.each do |data|
        array << add_column(data)
      end

      array << "    _.merge({"
      array << "      prop: 'action',"
      array << "      label: 'Action',"
      array << "      width: 100,"
      array << "      detail: true," if show_api_route
      array << "      edit: true," if update_api_route
      if destroy_api_route
        array << "      delete: {"
        array << "        handler: async ({ row }) => {"
        array << "          await this.$autoLoading(this.$request.delete(`/#{collection_name}/${row.id}`));"
        array << "          this.$message.success('Destroy successfully.');"
        array << "          this.$route.params.id ? this.$router.push({ name: '#{collection_name}.index' }) : this.fetchData();"
        array << "        }"
        array << "      }"
      end
      array << "    }, actionColumn)"
      array << "  ]"

      array.join("\n")
    end

    def add_column(data)
      array = []

      array << "    {"
      array << "      prop: '#{data[:prop]}',"
      array << "      label: '#{data[:label]}',"
      array << "      width: #{data[:width]}," if data[:width]
      array << "      sort: 'order_by'," if data[:sort]

      if data[:hide_in_table] || data[:hide_in_detail]
        hide_in_array = []
        hide_in_array << "hide-in-table" if data[:hide_in_table]
        hide_in_array << "hide-in-detail" if data[:hide_in_detail]
        action = hide_in_array.map { |str| "'#{str}'" } .join(", ")

        array << "      action: [#{action}],"
      end

      if data[:render_cell_component]
        if respond_to?("#{data[:render_cell_component]}_render_cell", true)
          render_cell_data_array = send("#{data[:render_cell_component]}_render_cell", data).split("\n")
          start_render_cell_data = render_cell_data_array.shift
          start_render_cell_data = render_cell_data_array.pop

          array << "      renderCell: (h, { row }) => {"
          array += render_cell_data_array.map { |str| " " * 6 + str }
          array << "      },"
        else
          array << "      renderCell: '#{data[:render_cell_component]}',"
        end
      end

      if data[:render_form]
        array << "      form: {"
        array << "        required: true," if data[:required]

        if respond_to?("#{data[:form_component]}_form", true)
          form_data_array = send("#{data[:form_component]}_form", data).split("\n")
          start_form_data = form_data_array.shift
          start_form_data = form_data_array.pop

          array += form_data_array.map { |str| " " * 6 + str }
        else
          array << "        component: '#{data[:form_component]}'"
        end

        array << "      }"
      end

      array << "    },"

      array
    end

    def select_form(data)
      <<~FILE
      {
        component: 'select',
        props: {
          defaultValue: '',
          clearable: true,
          options: [{ label: 'True', value: true }, { label: 'False', value: false }]
        }
      }
      FILE
    end

    def textarea_form(data)
      <<~FILE
      {
        component: 'input',
        props: {
          type: 'textarea',
          rows: 10
        }
      }
      FILE
    end

    def upload_form(data)
      <<~FILE
      {
        component: 'upload',
        props: {
          size: 5,
          limit: #{data[:attribute] == data[:attribute].pluralize ? 9 : 1},
          hint: 'Suggest size: 100x100'
        }
      }
      FILE
    end

    def email_form(data)
      <<~FILE
      {
        component: 'input',
        props: {
          type: 'email'
        }
      }
      FILE
    end

    def enum_form(data)
      <<~FILE
      {
        component: 'select',
        props: {
          clearable: #{data[:type] == "filter"},
          options: _.map(#{resource_class.name.underscore.upcase}_#{data[:attribute].pluralize.upcase}, (label, value) => ({ label, value }))
        }
      }
      FILE
    end

    def belongs_to_form(data)
      display_column_name = RELATION_DISPLAY_COLUMN_NAME.detect do |name|
        name.in?(data[:belongs_to_relation].klass.columns.map(&:name))
      end
      belongs_to_model = data[:belongs_to_relation].klass

      <<~FILE
      {
        component: 'select',
        props: {
         xRemotePreload: async () => {
            const { data } = await this.$request.get('/#{belongs_to_model.name.underscore.pluralize}', { params: { per_page: 100 } });
            return data.map(({ id, #{display_column_name} }) => ({ value: id, label: #{display_column_name} }))
          },
          xRemoteSearch: async (keyword) => {
            const params = { #{display_column_name}_cont: keyword };
            const { data } = await this.$request.get('/#{belongs_to_model.name.underscore.pluralize}', { params });
            return data.map(item => ({ value: item.id, label: item.#{display_column_name} }));
          }
        }
      }
      FILE
    end

    def textarea_render_cell(data)
      <<~FILE
      {
        if (!row.#{data[:attribute]}) {
          return '/'
        }
        return <span style="white-space: pre-wrap; word-break: break-all">{row.#{data[:attribute]}}</span>
      }
      FILE
    end

    def enum_render_cell(data)
      <<~FILE
      {
        // TODO 调整标签类型
        const type = ['warning', 'success', 'danger', 'info'][Object.keys(#{resource_class.name.underscore.upcase}_#{data[:attribute].pluralize.upcase}).indexOf(row.#{data[:attribute]})];
        return <el-tag type={type}>{#{resource_class.name.underscore.upcase}_#{data[:attribute].pluralize.upcase}[row.#{data[:attribute]}]}</el-tag>;
      }
      FILE
    end

    def belongs_to_render_cell(data)
      display_column_name = RELATION_DISPLAY_COLUMN_NAME.detect do |name|
        name.in?(data[:belongs_to_relation].klass.columns.map(&:name))
      end
      belongs_to_model = data[:belongs_to_relation].klass

      <<~FILE
      {
        if (row.#{data[:attribute]}) {
          const name = row.#{data[:belongs_to_relation].name}.#{display_column_name}
          if (permissionService.hasPermission('#{belongs_to_model.name.underscore.pluralize}.read')) {
            return <c-link-button to={{ name: '#{belongs_to_model.name.underscore.pluralize}.show', params: { id: row.#{data[:belongs_to_relation].foreign_key} } }}>{name}</c-link-button>
          } else {
            return name
          }
        } else {
          return '/'
        }
      }
      FILE
    end
  end
end
