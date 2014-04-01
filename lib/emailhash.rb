module EmailHash

  def EmailHash.hashme(message_headers)
    mail = Mail.new(message_headers)
    from = mail.from || "NOFROM"
    msgid = mail.message_id || "NOMSGID"
    date = mail.date ? mail.date.ctime : "NOTIME"
    return  "#{from}   #{msgid}   #{date}"
  end
  
end
