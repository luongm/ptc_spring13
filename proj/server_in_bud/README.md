## REST server inside Bud - API Documentation
**Note:** Only accepts and returns JSON data

### 1) List collections
Return a list of all user-defined (non-builtin) collections by the `/add_collection` API

    GET /collections


### 2) Add collection
Add a collection to the bud instance

    POST /add_collection
##### Parameters
* `type` type of collection, one of 'table', 'scratch'
* `name` name of collection
* `keys` a list of keys, ie. `[:test_key_1, :test_key_2]`
* `values` a list of values, ie. `[:test_val_1, :test_val_2, :test_val_3]`


### 3) Insert row
Insert row(s) into a collection

    POST /insert
##### Parameters
* `collection_name` the name of the collection to be added
* `op` the operation, one of `<=`, `<+` or `<~`
* `rows` the list of rows to be inserted, ie. `[ [:k1, :k2, :v1, :v2], [:k3, :k4, :v3, :v4] ]`


### 4) Remove row
Remove row(s) into a collection (with `<-`)

    POST /remove
##### Parameters
* `collection_name` the name of the collection to be removed
* `rows` the list of rows to be removed, ie. `[ [:k1, :k2, :v1, :v2], [:k3, :k4, :v3, :v4] ]`


### 5) List rule(s)
Get a list of rules currently associated with the bud instance

    GET /rules


### 6) Add rule
_**TODO:**  to be implemented_  
Add a rule to the bud instance

    POST /add_rule
##### Parameters
* `lhs` the table on the left side of the rule
* `op` the operation, one of `<=`, `<+`, `<~`, `<-`, `<+-` or `<=-`
* `rhs` the expression on the right side of the rule
