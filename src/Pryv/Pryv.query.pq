// Use this file to write queries to test your data connector
let
    //result = Pryv.Streams("https://chbvdemo.pryv.me:443/#/sharings/cj7c1i1r20pc00crcmndebzow")
    result = Pryv.Contents("https://techtest.bdb.pryv.tech/#/sharings/cj7sruoua000c0dnt4ie5n1cu", #datetime(2017, 9, 11, 0, 0, 0), #datetime(2017, 9, 21, 0, 0, 0), null, null, null, null, null, null, null, null, null)
in
    result