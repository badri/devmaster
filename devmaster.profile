<?php
/**
 * @file devshop.profile
 *
 * DevShop Installation Profile
 */

/**
 * Implements hook_install()
 */
function devmaster_install() {

  variable_set('install_profile', 'devmaster');

  // add support for nginx
  if (d()->platform->server->http_service_type === 'nginx') {
    module_enable(array('hosting_nginx'));
  }

  // Bootstrap and create all the initial nodes
  devmaster_bootstrap();

  // Finalize and setup themes, menus, optional modules etc
  devmaster_task_finalize();
}

function devmaster_bootstrap() {

  /* Default client */
  $node = new stdClass();
  $node->uid = 1;
  $node->type = 'client';
  $node->title = drush_get_option('client_name', 'admin');
  $node->status = 1;
  node_save($node);
  variable_set('hosting_default_client', $node->nid);
  variable_set('hosting_admin_client', $node->nid);

  $client_id = $node->nid;

  /* Default server */
  $node = new stdClass();
  $node->uid = 1;
  $node->type = 'server';
  $node->title = php_uname('n');
  $node->status = 1;
  $node->hosting_name = 'server_master';
  $node->services = array();

  /* Make it compatible with more than apache and nginx */
  $master_server = d()->platform->server;
  hosting_services_add($node, 'http', $master_server->http_service_type, array(
    'restart_cmd' => $master_server->http_restart_cmd,
    'port' => 80,
    'available' => 1,
  ));

  /* examine the db server associated with the hostmaster site */
  $db_server = d()->db_server;
  $master_db = parse_url($db_server->master_db);
  /* if it's not the same server as the master server, create a new node
   * for it */
  if ($db_server->remote_host == $master_server->remote_host) {
    $db_node = $node;
  } else {
    $db_node = new stdClass();
    $db_node->uid = 1;
    $db_node->type = 'server';
    $db_node->title = $master_db['host'];
    $db_node->status = 1;
    $db_node->hosting_name = 'server_' . $db_server->remote_host;
    $db_node->services = array();
  }
  hosting_services_add($db_node, 'db', $db_server->db_service_type, array(
    'db_type' => $master_db['scheme'],
    'db_user' => urldecode($master_db['user']),
    'db_passwd' => urldecode($master_db['pass']),
    'port' => 3306,
    'available' => 1,
  ));

  drupal_set_message(st('Creating master server node'));
  node_save($node);
  if ($db_server->remote_host != $master_server->remote_host) {
    drupal_set_message(st('Creating db server node'));
    node_save($db_node);
  }
  variable_set('hosting_default_web_server', $node->nid);
  variable_set('hosting_own_web_server', $node->nid);

  variable_set('hosting_default_db_server', $db_node->nid);
  variable_set('hosting_own_db_server', $db_node->nid);

  // Create the hostmaster platform & packages
  $node = new stdClass();
  $node->uid = 1;
  $node->title = 'Drupal';
  $node->type = 'package';
  $node->package_type = 'platform';
  $node->short_name = 'drupal';
  $node->old_short_name = 'drupal';
  $node->description = 'Drupal code-base.';
  $node->status = 1;
  node_save($node);
  $package_id = $node->nid;

  // @TODO: We need to still call these nodes "hostmaster" because the aliases are still @hostmaster and @platform_hostmaster
  $node = new stdClass();
  $node->uid = 1;
  $node->type = 'platform';
  $node->title = 'hostmaster';
  $node->publish_path = d()->root;
  $node->makefile = '';
  $node->verified = 1;
  $node->web_server = variable_get('hosting_default_web_server', 2);
  $node->platform_status = 1;
  $node->status = 1;
  $node->make_working_copy = 0;
  node_save($node);
  $platform_id = $node->nid;
  variable_set('hosting_own_platform', $node->nid);

  $instance = new stdClass();
  $instance->rid = $node->nid;
  $instance->version = VERSION;
  $instance->schema_version = drupal_get_installed_schema_version('system'); $instance->filename = '';
  $instance->version_code = 1;
  $instance->schema_version = 0;
  $instance->package_id = $package_id;
  $instance->status = 0;
  $instance->platform = $platform_id;
  hosting_package_instance_save($instance);

  // Create the hostmaster profile node
  $node = new stdClass();
  $node->uid = 1;
  $node->title = 'devmaster';
  $node->type = 'package';
  $node->old_short_name = 'hostmaster';
  $node->description = 'The Hostmaster profile.';
  $node->package_type = 'profile';
  $node->short_name = 'devmaster';
  $node->status = 1;
  node_save($node);
  $profile_id = $node->nid;

  $instance = new stdClass();
  $instance->rid = $node->nid;
  $instance->version = VERSION;
  $instance->filename = '';
  $instance->version_code = 1;
  //$instance->schema_version = drupal_get_installed_schema_version('system');
  $instance->schema_version = 0;
  $instance->package_id = $profile_id;
  $instance->status = 0;
  $instance->platform = $platform_id;
  hosting_package_instance_save($instance);

  // Create the main Aegir site node
  $node = new stdClass();
  $node->uid = 1;
  $node->type = 'site';
  $node->title = d()->uri;
  $node->platform = $platform_id;
  $node->client = $client_id;
  $node->db_name = '';
  $node->db_server = $db_node->nid;
  $node->profile = $profile_id;
  $node->import = true;
  $node->hosting_name = 'hostmaster';
  $node->site_status = 1;
  $node->verified = 1;
  $node->status = 1;
  node_save($node);

  // Set the frontpage
  variable_set('site_frontpage', 'devshop');

  // Set the sitename
  variable_set('site_name', 'DevShop');

  // do not allow user registration: the signup form will do that
  variable_set('user_register', 0);

  // This is saved because the config generation script is running via drush, and does not have access to this value
  variable_set('install_url' , $GLOBALS['base_url']);

  // enable the betterlogin private site functionality
  variable_set('betterlogin_private', 1);

  // Disable backup queue for sites by default.
  // variable_set('hosting_backup_queue_default_enabled', 0);

  // This is saved because the config generation script is running via drush, and does not have access to this value
  variable_set('install_url' , $GLOBALS['base_url']);
}

function devmaster_task_finalize() {
  drupal_set_message(st('Configuring menu items'));

  install_include(array('menu'));
  $menu_name = variable_get('menu_primary_links_source', 'primary-links');

  // @TODO - seriously need to simplify this, but in our own code i think, not install profile api
//  $items = install_menu_get_items('hosting/projects');
//  $item = db_fetch_array(db_query("SELECT * FROM {menu_links} WHERE mlid = %d", $items[0]['mlid']));
//  $item['menu_name'] = $menu_name;
//  $item['customized'] = 1;
//  $item['weight'] = 3;
//  $item['options'] = unserialize($item['options']);
//  install_menu_update_menu_item($item);
//
//  $items = install_menu_get_items('hosting/servers');
//  $item = db_fetch_array(db_query("SELECT * FROM {menu_links} WHERE mlid = %d", $items[0]['mlid']));
//  $item['menu_name'] = $menu_name;
//  $item['customized'] = 1;
//  $item['weight'] = 2;
//  $item['options'] = unserialize($item['options']);
//  install_menu_update_menu_item($item);
//
//  $items = install_menu_get_items('user');
//  $item = db_fetch_array(db_query("SELECT * FROM {menu_links} WHERE mlid = %d", $items[0]['mlid']));
//  $item['menu_name'] = $menu_name;
//  $item['customized'] = 1;
//  $item['options'] = unserialize($item['options']);
//  install_menu_update_menu_item($item);
//
//  $items = install_menu_get_items('logout');
//  $item = db_fetch_array(db_query("SELECT * FROM {menu_links} WHERE mlid = %d", $items[0]['mlid']));
//  $item['menu_name'] = $menu_name;
//  $item['customized'] = 1;
//  $item['weight'] = 1;
//  $item['options'] = unserialize($item['options']);
//  install_menu_update_menu_item($item);

  menu_rebuild();

  $theme = 'boots';
  drupal_set_message(st('Enabling "boots" theme'));
  install_disable_theme('bartik');
  install_default_theme('boots');
  system_theme_data();

  db_query("DELETE FROM {cache}");

  drupal_set_message(st('Configuring default blocks'));
//  install_add_block('devshop_hosting', 'devshop_tasks', $theme, 1, 5, 'header', 1);

  // @TODO: CREATE DEVSHOP ROLES!
  drupal_set_message(st('Configuring roles'));
//  install_remove_permissions(install_get_rid('anonymous user'), array('access content', 'access all views'));
//  install_remove_permissions(install_get_rid('authenticated user'), array('access content', 'access all views'));
//  install_add_permissions(install_get_rid('anonymous user'), array('access disabled sites'));
//  install_add_permissions(install_get_rid('authenticated user'), array('access disabled sites'));

  // Create administrator role
  $rid = install_add_role('administrator');
  variable_set('user_admin_role', $rid);

  // Hide errors from the screen.
  variable_set('error_level', 0);

  // Make sure blocks are setup properly.
  _block_rehash();

  node_access_rebuild();
}
