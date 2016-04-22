RHGS init scripts for RHEL7 base system
=======
Introduction
-----------
몇고객사에 다수의 글러스터 볼륨을 생성하면서, 디스크 초기화를 자동화하는 스크립트를 작성하였습니다. 기본적으로 brick 을 구성하기 위해서는 Raid 구성에 맞추어 lvm pool 을 만들어야 합니다. 이것은 snapshot 기능을 위한 필수 사항이며, zeroing 옵션도 성능을 위해서 권고 됩니다. 관련한 세부적인 설정들을 gdeploy 등으로 할 수도 있습니다.


    function list:
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
