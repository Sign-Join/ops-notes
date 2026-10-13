# K8S漏洞

# K8S漏洞

# CVE\-2016\-2183\-以及RSA漏洞公告

6443、8443、10250

[https://ecloud\.10086\.cn/op\-help\-center/faq/article/75122](https://ecloud.10086.cn/op-help-center/faq/article/75122)

需要注意版本

### RSA漏洞

#### Master 节点：修复 6443 \+ 8443 端口

```plain
cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml

- --tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
```

#### 所有节点（Master \+ Node）：修复 10250 端口

```plain
cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak
vi /var/lib/kubelet/config.yaml

tlsCipherSuites: [TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384]
```

重启kubelet生效

```plain
systemctl daemon-reload
systemctl restart kubelet
```

### 验证：

```plain
openssl s_client -connect <节点IP>:<端口> -cipher '3DES' -tlsextdebug

# 测试是否支持静态 RSA 密钥交换
openssl s_client -connect <节点IP>:<端口> -cipher 'RSA' -tlsextdebug
```

