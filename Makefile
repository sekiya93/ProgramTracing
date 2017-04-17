#
# Time-stamp: <2014-04-28 15:09:43 sekiya> 
#

# ディレクトリ
SOURCEDIR = $(HOME)/src/eLearning/programming_skill/web
TARGETDIR = /usr/local/plack/tracing

# コマンド
RSYNC = /usr/bin/rsync
RM = /bin/rm -f

# Sakura
SAKURASERVER = www9082ug.sakura.ne.jp

all: 
	make clean 
	make install

install:
	$(RSYNC) --exclude '*~' --exclude 'exam/' -e ssh -avz $(SOURCEDIR)/ $(SAKURASERVER):$(TARGETDIR)/
#	$(RSYNC) -e ssh -avz $(SOURCEDIR)/ 10.8.0.1:$(TARGETDIR)/

get_exam:
	$(RSYNC) --exclude '*~' -e ssh -avz $(SAKURASERVER):$(TARGETDIR)/exam/ $(SOURCEDIR)/exam/

put_exam:
	$(RSYNC) --exclude '*~' -e ssh -avz $(SOURCEDIR)/exam/ $(SAKURASERVER):$(TARGETDIR)/exam/

put_exam_to_sakura:
	$(RSYNC) --exclude '*~' -e ssh -avz $(SOURCEDIR)/exam/ $(SAKURASERVER):$(TARGETDIR)/exam/

put_code: 
	$(RSYNC) --exclude '*~' -e ssh -avz $(SOURCEDIR)/exam/ruby_code/ $(SAKURASERVER):$(TARGETDIR)/exam/ruby_code/

clean: 
	$(RM) *~ 
