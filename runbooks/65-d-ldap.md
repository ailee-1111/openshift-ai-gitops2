# 65-d — LDAP/AD 연동 검증 (No.45/46)

## 목적

클러스터 내 OpenLDAP을 배포하여 LDAP/AD 연동 프로세스를 검증한다. 테스트 조직도를 구성하고, OpenShift OAuth LDAP IdP + RHOAI Dashboard 로그인 + Group Sync + RBAC까지 E2E 검증.

## 전제 조건

- [ ] cluster-admin 권한
- [ ] 환경변수: `CLUSTER_API_URL`, `POC_NAMESPACE`

## 실행

### 1. OpenLDAP 배포

~~~bash
oc apply -k infra/poc/ldap/
oc wait -n poc-ldap deployment/openldap --for=condition=Available --timeout=120s
oc get pods -n poc-ldap
~~~

### 2. LDAP 연결 테스트

~~~bash
LDAP_POD=$(oc get pods -n poc-ldap -l app=openldap -o jsonpath='{.items[0].metadata.name}')
oc exec -n poc-ldap ${LDAP_POD} -- ldapsearch -x -H ldap://localhost:1389 \
  -D "cn=admin,dc=mobis,dc=local" -w admin1234 \
  -b "dc=mobis,dc=local" "(objectClass=*)" dn
~~~

### 3. OAuth LDAP Identity Provider

~~~bash
oc create secret generic ldap-bind-password \
  -n openshift-config \
  --from-literal=bindPassword=admin1234 \
  --dry-run=client -o yaml | oc apply -f -

oc apply -f - <<'EOF'
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: poc-ldap
      type: LDAP
      mappingMethod: claim
      ldap:
        url: "ldap://openldap.poc-ldap.svc.cluster.local:389/ou=users,dc=mobis,dc=local?uid"
        insecure: true
        bindDN: "cn=admin,dc=mobis,dc=local"
        bindPassword:
          name: ldap-bind-password
        attributes:
          id: ["dn"]
          email: ["mail"]
          name: ["cn"]
          preferredUsername: ["uid"]
EOF
~~~

### 4. LDAP 사용자 로그인

~~~bash
oc wait -n openshift-authentication deployment/oauth-openshift \
  --for=condition=Available --timeout=300s

oc login ${CLUSTER_API_URL} \
  --username=dev-user1 --password=password1 \
  --insecure-skip-tls-verify=true
oc whoami
~~~

### 5. Group Sync

~~~bash
oc adm groups sync \
  --sync-config=infra/poc/ldap/ldap-group-sync.yaml \
  --confirm
oc get groups
~~~

### 6. Group RBAC

~~~bash
oc adm policy add-role-to-group edit dev-team -n ${POC_NAMESPACE}
oc get rolebindings -n ${POC_NAMESPACE} | grep dev-team
~~~

## 검증

| 항목 | 기준 | 판정 |
|------|------|------|
| OpenLDAP Pod | Running | PASS/FAIL |
| LDAP 사용자 로그인 | whoami=dev-user1 | PASS/FAIL |
| Group Sync | dev-team 존재 | PASS/FAIL |
| RBAC | RoleBinding 적용 | PASS/FAIL |

## 정리

~~~bash
oc delete -k infra/poc/ldap/ --ignore-not-found
oc delete secret ldap-bind-password -n openshift-config --ignore-not-found
~~~

## 실측 시도 (2026-05-16)

| 항목 | 결과 |
|------|------|
| bitnami/openldap | Docker Hub pull 불가 (rate limit/접근 제한) |
| 상태 | **절차 준비 완료** — IaC+런북+OAuth CR 구성 확인 |

> 해소: Docker Hub pull secret 추가 또는 고객 LDAP으로 직접 연동

## 실패 시

- **ImagePullBackOff** → Docker Hub pull secret 또는 내부 미러
- **LDAP 연결** → svc DNS 확인
- **OAuth** → `oc get events -n openshift-authentication`

## 다음 단계

→ `runbooks/75-platform-ops-validation.md`
