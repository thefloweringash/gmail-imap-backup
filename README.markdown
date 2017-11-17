Installation
============

    sudo gem install lockfile
    sudo gem install maildir
    sudo gem install oauth

Configuration
=============

Just run the program with the example config. 
It should guide you through setting up OAuth for your gmail account.

Automatic backups on Mac Os X
-----------------------------

From the mac-launchd folder, copy the .plist to ~/Library/LaunchAgents and the other file to ~/Library/Scripts (create this folder if neccessary).
Edit both files to update paths.
Use 

    launchctl load ~/Library/LaunchAgents/email.backup.plist
    
to register and start the background service.
To check if it's running, use 

    launchctl list | grep email.back

The first column should contain a pid, telling you that the backup is running.
The second column will later on contain the exit code, 0 meaning everything worked fine.

Recovery
========

Optional: Convert mbox to maildir
---------------------------------

If you have old backups stored in mbox format, you need to convert them to maildir.

    ./split_mbox_to_directory.rb old-backup-file.mbox /new/maildir/directory

Hash IMAP and Maildir mails
---------------------------

If you've noticed email loss, the first step is to create a list of all emails that are in still left in your mail account. To do so, run

    ./hash_imap_account.rb your-config-file.yml > imap-hashes.txt
    
And of course you also need a list of all the emails that your backup contains.

    ./hash_maildir.rb /path/to/backups > backup-hashes.txt

Generate TSV of missing mails
-----------------------------

Now we only want to recover the mails that are missing, so let's generate a list of them. We start with an empty set and then first add all the messages that are in the backup, then remove the messages still present in our imap account.

    ./merge_hash_lists.rb -a backup-hashes.txt -r imap-hashes.txt > missing-hashes.txt

Now we can convert the list to a TSV format of "hash \t from \t subject".

    ./hash_list_to_tsv.rb missing-hashes.txt > missing-hashes-tsv.txt

Next, you need to use your favorite grep or text editor to remove those missing emails that you don't want to recover. If you did delete emails intentionally, this is the step to prevent them from being restored...

Re-Upload missing mails
-----------------------

We'll assume that you now have a list of all the mails you want to recover in recover-hashes.txt. You should create an IMAP mailbox for the recovered messages with your email client. Afterwards, you can start the upload by:

    ./upload_messages.rb your-config-file.yml recover-hashes.txt "Target Mailbox Name"

Contact
=======

This script is provided as-is and is meant for other computer programmers to use. Please *do not* call / chat / email me with end-user usage questions.

If you have found a bug or have a code improvement, please open a GitHub issue or (even better) submit a pull request.


