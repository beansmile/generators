## How to use
`rails generate admin_view MODEL`

## Preconditions

以model为user为例

* 必须有AdminAPI::API::Entities::UserDetail这个entity
* 必须有AdminAPI::API::V1::Users这个API

## What will be done

`rails generate admin_view user`

### 根据AdminAPI::API::V1::Users的CRUD API生成对应的route和页面

### 根据AdminAPI::API::V1::Users index API的params生成对应的filter
#### Example

如果index API的params如下

```
params do
  optional :nickname_cont
  optional :is_blocked_eq
end
```

将会生成下面那样的管理后台index页面filter参数

```
[
  {
    prop: 'nickname_cont',
    label: 'Nickname',
    form: {
      component: 'input'
    },
  },
  {
    prop: 'is_blocked_eq',
    label: 'Is blocked',
    form: {
      component: 'select',
      props: {
        defaultValue: '',
        clearable: true,
        options: [{ label: 'True', value: true }, { label: 'False', value: false }]
      }
    },
  },
]
```

### 根据AdminAPI::API::Entities::UserDetail生成对应的columns

```
expose :id
expose :avatar
expose :name
expose :phone
expose :email
expose :introduction
expose :created_at
expose :updated_at
```

将会生成下面那样的管理后台columns参数

```
[
  {
    prop: 'id',
    label: 'ID',
    width: 80,
    sort: 'order_by',
  },
  {
    prop: 'avatar',
    label: 'Avatar',
    renderCell: 'image',
    form: {
      required: true,
      component: 'upload',
      props: {
        size: 1,
        hint: 'Suggest size: 100x100'
      }
    }
  },
  {
    prop: 'name',
    label: 'Name',
    sort: 'order_by',
    form: {
      required: true,
      component: 'input'
    }
  },
  {
    prop: 'phone',
    label: 'Phone',
    sort: 'order_by',
    form: {
      required: true,
      component: 'input'
    }
  },
  {
    prop: 'email',
    label: 'Email',
    sort: 'order_by',
    form: {
      required: true,
      component: 'input',
      props: {
        type: 'email'
      }
    }
  },
  {
    prop: 'introduction',
    label: 'Introduction',
    action: ['hide-in-table'],
    renderCell: (h, { row }) => {
      if (!row.introduction) {
        return '/'
      }
      return <span style="white-space: pre-wrap; word-break: break-all">{row.introduction}</span>
    },
    form: {
      required: true,
      component: 'input',
      props: {
        type: 'textarea',
        rows: 10
      }
    }
  },
  {
    prop: 'created_at',
    label: 'Created at',
    action: ['hide-in-table'],
    renderCell: 'time',
  },
  {
    prop: 'updated_at',
    label: 'Updated at',
    action: ['hide-in-table'],
    renderCell: 'time',
  }
]
```
