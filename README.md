RHGS init scripts for RHEL7 base system
=======
Introduction
-----------
디스크 초기화를 자동화하는 스크립트를 작성하였습니다. 기본적으로 brick 을 구성하기 위해서는 Raid 구성에 맞추어 lvm pool 을 만들어야 합니다. 이것은 snapshot 기능을 위한 필수 사항이며, zeroing 옵션도 성능을 위해서 권고 됩니다. 관련한 세부적인 설정들을 gdeploy 등으로 할 수도 있습니다. gdeploy 를 이용할 경우 python 과 ansible 이 사전 설치 되어 있어야 합니다.

인터프린터로 bash 를 이용하기 때문에 sh <script-name.sh> 같은 형태로 실행 할 경우, 정상적으로 동작되지 않을 수 있습니다. 다음과 같은 형태로 실행하십시오. 

실행방법: 
```{r, engine='bash', count_lines}
# chmod +x ./rhgs-init-script.sh 
# ./rhgs-init-script.sh
```

### 구성 내역:
* rhgs-init-script.sh
  rhgs 의 서버노드를 초기화 하고 brick 구성을 하는 스크립트, 볼륨은 별도의 cli 명령을 통하여 구성하여야 합니다. 
* gluster.conf
  각 서버의 brick 구성을 위한 세부 설정값 및 디바이스 정보를 저장한 설정 파일
* gvp-client.sh
  클라이언트에서 rhgs 를 마운트 하여 사용할때 볼륨의 성능을 측정하기 위한 스크립트. gluster volume profile 기능을 이용할 경우 gluster-profile-analysis (url : https://github.com/cristov/gluster-profile-analysis ) 을 이용하여 fops 의 세부적인 성능 데이터를 볼 수 있습니다.
* netperf-stream-pairs.sh
  netperf 를 이용하여 10GE 이상의 네트워크에서 NIC 가 정상적으로 동작하는지 테스트 하는 스크립트
* size_histogram.py
  기존 운영하는 볼륨의 file size 의 표준분포를 계산하여 brick 의 데이터 구조를 설정하기 위한 기반 데이터를 추출하는 스크립트

### rhgs-init-script.sh function list:
    * add_firewallrule
        firewalld  방화벽 구성을 richrule 로 Gluster 서비스를 위한 포트들을 열어줍니다.
	* mk_gpt_lvmpart
        gpt 파티션을 만들고 lvm 으로 파티션을 태깅합니다.
	* create_pv 
        lvm 으로 태깅된 파티션을 pv 로 등록합니다.
	* create_vg 
        rhgs 볼륨 그룹을 만들고 data-alignment 를 설정합니다.
	* create_lv 
        lv-pool 을 생성하고, pool-meta , cdata 등을 생성하여 할당 합니다. pool-meta 데이터는 lv-pool 의 0.1% 사이즈를 권고하나 16GB 가 최대구성 가능한 사이즈로 일반적으로 lv 사이즈가 16TB를 넘기는 경우가 많아 16GB로 생성합니다.      
	* create_logdevice 
        fops 의 inode opreation 성능을 증가시키기 위하여, external log device 를 구성합니다. 이렇게 구성할 경우 snapshot 을 사용할 수 없게 됩니다. 권고하지 않는 구성이지만, 성능 극대화를 원하는 고객들을 위해서 테스크를 하느라 만들었습니다.
	* mkfsb
        생성된 brick 을 fstab 에 등록하고, 자동으로 마운트 되도록 합니다. 
	* mountb
        브릭을 마운트하여 사용할 수 있는 상태로 만듭니다.
	* enable_dmcache
        ssd 를 이용하여 dmcache 를 구성합니다. spindle disk 보다 iops 가 높은 디스크로 구성하여야합니다.
	* send_config
        kernel 튜닝 파라미터와 Limit 설정등을 변경합니다.

Red Hat Gluster Storage [link](https://www.redhat.com/ko/technologies/storage)
