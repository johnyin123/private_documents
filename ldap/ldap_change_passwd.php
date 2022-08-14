<?php
$message = array();

function changePassword($user,$oldPassword,$newPassword,$newPasswordCnf){
  global $message;

  $server = "localhost";
  $dn = "ou=People,dc=example,dc=com";
  $userid = $user;

  $user = "uid=".$user.",".$dn;
  error_reporting(0);
  ldap_connect($server);
  $con = ldap_connect($server);
  ldap_set_option($con, LDAP_OPT_PROTOCOL_VERSION, 3);

  // bind anon and find user by uid
  $sr = ldap_search($con,$dn,"(uid=*)");
  $records = ldap_get_entries($con, $sr);

  $message[] = "Username: " . $userid;
  //$message[] = "DN: " . $user;
  //$message[] = "Current Pass: " . $oldPassword;
  //$message[] = "New Pass: " . $newPassword;

  /* try to bind as that user */
  if (ldap_bind($con, $user, $oldPassword) === false) {
    $message[] = "Error E101 - Current Username or Password is wrong.";
    return false;
  }
  if ($newPassword != $newPasswordCnf ) {
    $message[] = "Error E102 - Your New passwords do not match! ";
    return false;
  }
  if (strlen($newPassword) < 4 ) {
    $message[] = "Error E103 - Your new password is too short! ";
    return false;
  }
  if (!preg_match("/[0-9]/",$newPassword)) {
    $message[] = "Error E104 - Your new password must contain at least one digit. ";
    return false;
  }
  if (!preg_match("/[a-zA-Z]/",$newPassword)) {
    $message[] = "Error E105 - Your new password must contain at least one letter. ";
    return false;
  }
  if (!preg_match("/[A-Z]/",$newPassword)) {
    $message[] = "Error E106 - Your new password must contain at least one uppercase letter. ";
    return false;
  }
  if (!preg_match("/[a-z]/",$newPassword)) {
    $message[] = "Error E107 - Your new password must contain at least one lowercase letter. ";
    return false;
  }

  /* change the password finally */
  $entry = array();
  $entry["userPassword"] = "{SHA}" . base64_encode( pack( "H*", sha1( $newPassword ) ) );

  if (ldap_modify($con,$user,$entry) === false){
    $message[] = "E200 - Your password cannot be change, please contact the administrator.";
  } else {
    $message[] = " Your password has been changed. ";
    //mail($records[0]["mail"][0],"Password change notice : ".$userid," Your password has just been changed.");
  }
}

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <title>Change your LDAP password</title>
  <style type="text/css">
  body { font-family: Verdana,Arial,Courier New; font-size: 0.7em;  }
  input:focus { background-color: #eee; border-color: red; }
  th { text-align: right; padding: 0.8em; }
  #container { text-align: center; width: 500px; margin: 5% auto; }
  ul { text-align: left; list-style-type: square; }
  .msg { margin: 0 auto; text-align: center; color: navy;  border-top: 1px solid red;  border-bottom: 1px solid red;  }
  </style>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
</head>
<body>
  <div id="container">
    <h2>Change your LDAP password</h2>
<ul>
  <li> Your new password must be 8 characters long and contain at least one letter and one digit. </li>
</ul>
    <form action="<?php print $_SERVER['PHP_SELF']; ?>" name="passwordChange" method="post">
      <table style="width: 400px; margin: 0 auto;">
        <tr><th>Username:</th><td><input name="username" type="text" size="20" autocomplete="off" /></td></tr>
        <tr><th>Old password:</th><td><input name="oldPassword" size="20" type="password" /></td></tr>
        <tr><th>New password:</th><td><input name="newPassword1" size="20" type="password" /></td></tr>
        <tr><th>New password (again):</th><td><input name="newPassword2" size="20" type="password" /></td></tr>
        <tr><td colspan="2" style="text-align: center;" >
          <input name="submitted" type="submit" value="Change Password"/>
          <button onclick="$('frm').action='changepassword.php';$('frm').submit();">Cancel</button>
        </td></tr>
      </table>
    </form>
    <div class="msg"><?php
      if (isset($_POST["submitted"])) {
        changePassword($_POST['username'],$_POST['oldPassword'],$_POST['newPassword1'],$_POST['newPassword2']);
        foreach ( $message as $one ) { echo "<p>$one</p>"; }
      } ?>
    </div>
  </div>
</body>
</html>
