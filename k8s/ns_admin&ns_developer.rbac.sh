cat <<EOF > ns_admin.yml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: namespace-admin
  namespace: ${USER_NS}
rules:
  - apiGroups:
    - ""
    - extensions
    - apps
    resources:
    - '*'
    verbs:
    - '*'
  - apiGroups:
    - batch
    resources:
    - jobs
    - cronjobs
    verbs:
    - '*'
  - apiGroups:
    - rbac.authorization.k8s.io
    resources:
    - rolebindings
    - roles
    verbs:
    - '*'
EOF
cat <<EOF > ns_admin.rb.yml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: namespace-admin-role-binding
  namespace: ${USER_NS}
subjects:
- kind: ${TYPE}
  name: ${USER}
roleRef:
  kind: Role
  name: namespace-admin
  apiGroup: rbac.authorization.k8s.io
EOF
cat <<EOF > ns_developer.yml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: namespace-developer
  namespace: ${USER_NS}
rules:
  - apiGroups:
    - ""
    resources:
    - bindings
    - componentstatuses
    - configmaps
    - endpoints
    - events
    - limitranges
    - namespaces
    - nodes
    - persistentvolumeclaims
    - persistentvolumes
    - pods
    - pods/log
    - podtemplates
    - replicationcontrollers
    - resourcequotas
    - serviceaccounts
    - services
    - secrets
    verbs:
    - get
    - list
    - watch
  - apiGroups:
    - extensions
    resources:
    - '*'
    verbs:
    - get
    - list
    - watch
  - apiGroups: 
    - "apps"
    resources: 
    - deployments/scale
    - replicasets/scale
    verbs: 
    - create
    - delete
    - get
    - patch
    - list
    - watch
    - update
  - apiGroups:
    - rbac.authorization.k8s.io
    resources:
    - clusterrolebindings
    - clusterroles
    verbs:
    - get
    - list
    - watch
  - apiGroups:
    - batch
    resources:
    - '*'
    verbs:
    - get
    - list
    - watch
EOF
cat <<EOF > ns_developer.rb.yml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: namespace-developer-role-binding
  namespace: ${USER_NS}
subjects:
- kind: ${TYPE}
  name: ${USER}
roleRef:
  kind: Role
  name: namespace-developer
  apiGroup: rbac.authorization.k8s.io
EOF
