local kp =
  (import 'kube-prometheus/main.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  // (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  // (import 'kube-prometheus/addons/node-ports.libsonnet') +
  // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
  // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
      },
      alertmanager+: {
        config: importstr 'alertmanager-config.yaml',
      },
      grafana+:{
        config+: {
            sections: {
              date_formats: { default_timezone: 'UTC' },
              "auth": {
                "disable_login_form": true,
                "oauth_auto_login": true,
                "disable_signout_menu": false,
                "signout_redirect_url": "https://keycloak.kam.obmondo.com/auth/realms/devops/protocol/openid-connect/logout?redirect_uri=https://grafana.kam.obmondo.com"
              },
              "server": {
                "root_url": "https://grafana.kam.obmondo.com"
              },
              "auth.generic_oauth": {
                "enabled": true,
                "allow_sign_up": true,
                "scopes": "openid profile email",
                "name": "Keycloak",
                "auth_url": "https://keycloak.kam.obmondo.com/auth/realms/devops/protocol/openid-connect/auth",
                "token_url": "https://keycloak.kam.obmondo.com/auth/realms/devops/protocol/openid-connect/token",
                "api_url": "https://keycloak.kam.obmondo.com/auth/realms/devops/protocol/openid-connect/userinfo",
                "client_id": "grafana",
                "role_attribute_path": "contains(not_null(roles[*],''), 'Admin') && 'Admin' || contains(not_null(roles[*],''), 'Editor') && 'Editor' || contains(not_null(roles[*],''), 'Viewer') && 'Viewer'|| ''"
            }
          } 
        }
      }
    },

    alertmanager+: {
      alertmanager+: {
        spec+: {
          logLevel: 'debug',  // So firing alerts show up in log
          "useExistingSecret": true,
          "secrets": [
            "obmondo-clientcert"
          ]
        },
      },
    },
    prometheus+:: {
      prometheus+: {
        spec+: {  
          storage: {  
            volumeClaimTemplate: { 
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '10Gi' } },
                storageClassName: 'rook-ceph-block',
              },
            },
          },  
        },  
      },  
    },
  };

{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
