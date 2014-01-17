FROM stackbrew/ubuntu:13.10

RUN apt-get -y update
RUN apt-get install -y apt-utils
RUN apt-get install -y nodejs npm git
RUN ln -s /usr/bin/nodejs /usr/bin/node
RUN npm install -g bower coffee-script
RUN git clone https://github.com/xhochy/abookofmusic.git
RUN cd abookofmusic && bower --allow-root install
RUN cd abookofmusic && npm install

ADD conf.js abookofmusic/conf.js

CMD cd abookofmusic && coffee app.coffee
