#cloud-config
hostname: {{ vm_name | default('vmsrv', true) }}
locale: {{ vm_locale | default('zh_CN.UTF-8', true) }}
timezone: {{ vm_timezone | default('Asia/Shanghai', true) }}
ssh_pwauth: true
users:
  # - default
  - name: {{ vm_user | default('clouduser', true) }}
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    # mkpasswd tsd@2023
    passwd: "$y$j9T$w03ZqJfTwNHoZLiiey26e1$bOaegd/YRirhGlEeQciVnEFPFO1dI2pwqKp4adctLsD"
    ssh_authorized_keys:
      - ssh-rsa {{ vm_sshkey | default('AAAAB3NzaC1yc2EAAAADAQABAAABgQDIcCEBlGLWfQ6p/6/QAR1LncKGlFoiNvpV3OUzPEoxJfw5ChIc95JSqQQBIM9zcOkkmW80ZuBe4pWvEAChdMWGwQLjlZSIq67lrpZiql27rL1hsU25W7P03LhgjXsUxV5cLFZ/3dcuLmhGPbgcJM/RGEqjNIpLf34PqebJYqPz9smtoJM3a8vDgG3ceWHrhhWNdF73JRzZiDo8L8KrDQTxiRhWzhcoqTWTrkj2T7PZs+6WTI+XEc8IUZg/4NvH06jHg8QLr7WoWUtFvNSRfuXbarAXvPLA6mpPDz7oRKB4+pb5LpWCgKnSJhWl3lYHtZ39bsG8TyEZ20ZAjluhJ143GfDBy8kLANSntfhKmeOyolnz4ePf4EjzE3WwCsWNrtsJrW3zmtMRab7688vrUUl9W2iY9venrW0w6UL7Cvccu4snHLaFiT6JSQSSJS+mYM5o8T0nfIzRi0uxBx4m9/6nVIl/gs1JApzgWyqIi3opcALkHktKxi76D0xBYAgRvJs=', true) }} root@liveos
write_files:
  - path: /root/.cloud.init
    owner: 'root:root'
    permissions: '0600'
    append: true
    content: |
      init cloud {{ vm_uuid | default('', true) }} {{ vm_create | default('', true) }}
runcmd:
  - passwd -d root
  - echo "{{ vm_user | default('clouduser', true) }}:{{ vm_password | default('tsd@2023', true) }}" | chpasswd
growpart:
  mode: auto
  devices: ['/']
swap:
  size: 2G
bootcmd:
  - echo "BOOT OK"
  - touch /etc/cloud/cloud-init.disabled
final_message: |
  cloud-init has finished
  datasource: $datasource
