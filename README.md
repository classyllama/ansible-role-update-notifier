# Ansible Role: Update Notifier 

This role provides a cron script that notifies via email when the running service version doesn't match with the installed version (i.e. typically when the package was updated by yum-cron but the service
was not reloaded).
Currently, it supports MySQL, Redis, and ElasticSearch services.

## Requirements

None.

## Role Variables

See `defaults/main.yml` for details.

## Dependencies

None.

## Example Playbook

    - hosts: all
      roles:
         - { role: classyllama.updatenotifier, tags: updatenotifier, when: use_classyllama_updatenotifier | default(false) }

## License

This work is licensed under the MIT license. See LICENSE file for details.

