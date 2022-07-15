# Ansible Role: Update Notifier 

This role provides a cron script that notifies via email when the running service version doesn't match with the installed version (i.e. typically when the package was updated by yum-cron but the service was not reloaded).

Currently, it supports MySQL, Redis, and ElasticSearch services.

## Requirements

Installed SQLite (sqlite3), which is typically installed by default

## Role Variables

A list of emails:

    classyllama_updatenotifier_emails: "example@classyllama.com example2@classyllama.com"

Script/cron owner:

    classyllama_updatenotifier_username: "www-prod"
    classyllama_updatenotifier_group: "www-prod"

Working directory:

    classyllama_updatenotifier_dir: "/home/{{ classyllama_updatenotifier_username }}/updatenotifier"

Ability to enable/disable specific service:

    classyllama_updatenotifier_checkredis: 1
    classyllama_updatenotifier_checkmysql: 1
    classyllama_updatenotifier_checkelastic: 1

Access credentials and settings:

    classyllama_updatenotifier_redis_host: localhost
    classyllama_updatenotifier_redis_port: 6379
    classyllama_updatenotifier_elastic_host: localhost
    classyllama_updatenotifier_elastic_port: 9200
    classyllama_updatenotifier_elastic_user: "{{ es_api_basic_auth_username | default('elastic') }}"
    classyllama_updatenotifier_elastic_pass: "{{ es_api_basic_auth_password | default('changeme') }}"

Please note, MySQL credentials needs to be stored in ~/.my.cnf to get non-interactive access.

See `defaults/main.yml` for details.

## Dependencies

None.

## Example Playbook

    - hosts: all
      roles:
         - { role: classyllama.updatenotifier, tags: updatenotifier, when: use_classyllama_updatenotifier | default(false) }

## License

This work is licensed under the MIT license. See LICENSE file for details.
