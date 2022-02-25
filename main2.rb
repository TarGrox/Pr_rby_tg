require 'rexml/document'  
require 'nokogiri'
require 'open-uri'
require 'CSV'


class Parser_site

    PRODUCT_LINKS = "//ul[contains(@id, 'product_list')]//div[contains(@class, 'product-container')]//a[contains(@class, 'product_img_link')]/@href"
    PRODUCT_NAME = "//h1[contains(@class, 'product_main_name')]"
    PRODUCT_WEIGHT = "//div[contains(@class, 'product_attributes')]//fieldset[contains(@class, 'attribute_fieldset')]//label[contains(@class, 'label_comb_price')]/span[contains(@class, 'radio_label')]"
    PRODUCT_PRICE = "//div[contains(@class, 'product_attributes')]//fieldset[contains(@class, 'attribute_fieldset')]//label[contains(@class, 'label_comb_price')]/span[@class='price_comb']"
    PRODUCT_IMG = "//div[contains(@id, 'image-block')]//img[contains(@id, 'bigpic')]/@src"
    PRODUCT_ATTRS_FIELDSET = "//div[contains(@class, 'product_attributes')]//fieldset[contains(@class, 'attribute_fieldset')]"
    PRODUCT_PRICE_SPAN = "//span[contains(@id, 'our_price_display')]"
    PRODUCT_INF = "//div[contains(@class, 'pb-center-column')]"
    LINK_TO_NEXT_PAGE = "//head//link[@rel='next']/@href"        
    TOTAL_NUM_OF_PAGES_V1 = "//button[contains(@class, 'loadMore prev button lnk_view btn btn-default')]/@data-p"
    TOTAL_NUM_OF_PAGES_V2 = "//div[contains(@class, 'content_sortPagiBar')]//ul[contains(@class, 'pagination clearfix li_fl')]//li/a/span"

    def initialize()        
        @file_name = ""
        @count_pages_not_written = 0
        @count_pages_written = 0
    end

    def main_method

        puts("введите название файла без расширения:")
        @file_name = gets.chomp! + '.csv'
        opening_csv_for_writing_headers()

        puts("Введите ссылку на Категорию:...")
        link_to_category = gets.chomp!
        link = link_to_category

        total_num_of_pages = get_total_number_of_pages(link)

        puts("Начинаю сбор информации", "==========")
           
        i = 1
        until link == "" do
            doc = get_html(link)
        
            link = doc.xpath(LINK_TO_NEXT_PAGE).text
        
            puts("###########","Страница категории #{i} из #{total_num_of_pages}","###########")
        
            collecting_links_of_products(doc)

            i += 1
        end
        
        puts("страниц не записано: #{@count_pages_not_written}")
        puts("страниц записано: #{@count_pages_written}")
        puts("относительная погрешность: #{@count_pages_not_written.to_f/@count_pages_written*100}")        

        puts("==============","Все страницы пройдены","==============","Завершение работы")

    end

    
    def opening_csv_for_writing_headers()
        puts("Открытие файла для форматирования и предзаписи, создание заголовков таблицы")
        headers = ["name", "price", "image"]
        CSV.open(@file_name, "w") do |csv_f|
              csv_f << headers
        end
        puts("Файл успешно открыт")
    end
    
    def collecting_links_of_products(doc)

        puts("Получение ссылок на продукты на странице")
        links_ar = doc.xpath(PRODUCT_LINKS)

        links_ar.each_with_index do |pr_link,index|

            # передаем информацию Парсеру страницы продукта
            puts("... Продукт #{index+1} из #{links_ar.size} записывается - #{pr_link}")
            product_page_type_selector(pr_link)
        end
    end

    def product_page_type_selector(pr_link)

        puts("Открываем страницу товара")

        doc = get_html(pr_link) # получаем весь документ
        doc_product_inf = doc.at_xpath(PRODUCT_INF) # оставляем только информацию о самом продукте 
        # - это всё от Названия до Total Price

        if doc_product_inf.xpath(PRODUCT_ATTRS_FIELDSET + "//li").empty? == false # первый кейс
            puts("выбрали тип страницы товара")
            parsing_product_page_v1(doc_product_inf) 
            @count_pages_written += 1

        elsif doc_product_inf.xpath(PRODUCT_ATTRS_FIELDSET + "//select").empty? == false # второй кейс
            # parsing_product_page_v2(doc)
            puts("parsing_product_page_v2()")
            @count_pages_not_written += 1

        elsif doc_product_inf.xpath(PRODUCT_ATTRS_FIELDSET).empty? == true # третий case без вариантов размещений            
            puts("выбрали тип страницы товара")
            parsing_product_page_v3(doc_product_inf)
            @count_pages_written += 1

        else
            puts("unknown error in selector, #{pr_link}")
            @count_pages_not_written += 1
        end

        
        # //form id = "buy_block"
        #     //div class = "box-info-product"
        #         //div class = "product_attributes"
        #             //div id = "attributes"
        #                 //fieldset class = "attribute_fieldset"
        #                     //div class = "attribute_list"
        #                         //ul class = "attribute_radio_list pundaline-variations"
        #                             //li class = "????" # !!!!!!!!!! сами продукты # <- обычный case
        #                     //select name = "???" # !!!!!!!!!! <- case с селектором
        #         field is empty # !!!!!!!!! <- case без выбора в принципе
    end
    
    def parsing_product_page_v1(doc)

        # название
        pr_name = doc.xpath(PRODUCT_NAME).map { |e| e.text.gsub(/,/, '.').strip }
        # граммовка:
        weight_ar = doc.xpath(PRODUCT_WEIGHT).map { |e| e.text.gsub(/,/, '.') }
        # цена:
        price_ar = doc.xpath(PRODUCT_PRICE).map { |e| e.text.match(/\d*\.\d*/) }
        # ссылки на картинки
        img_link_ar = doc.xpath(PRODUCT_IMG).map(&:text)

        puts("закончили сбор информации со страницы")

        writing_in_file_new_inf(pr_name, price_ar, img_link_ar, weight_ar)
    end

    def parsing_product_page_v2()
        # https://www.petsonic.com/set-dental-para-perros.html#/3429-sabor-fresa
        # https://www.petsonic.com/comida-humeda-specific-ciw-digestive-support-para-perros-con-problemas-digestivos.html

        # цена обновляется с помощью JS - то есть нужно прожимать select, после этого подгружается инфа

        # решать такой тип страниц планирую с помощью watir 
        # http://watir.com/guides/form-example/
        # https://ru.stackoverflow.com/questions/767309/watir-ruby-%D0%B2%D0%BE%D0%B7%D0%B2%D1%80%D0%B0%D1%89%D0%B0%D0%B5%D1%82-%D0%BE%D1%88%D0%B8%D0%B1%D0%BA%D1%83-%D0%BF%D1%80%D0%B8-%D0%BF%D0%BE%D0%BF%D1%8B%D1%82%D0%BA%D0%B5-%D0%BD%D0%B0%D0%B6%D0%B0%D1%82%D1%8C-%D0%BD%D0%B0-%D0%BA%D0%BD%D0%BE%D0%BF%D0%BA%D1%83
        
    end

    def parsing_product_page_v3(doc)
        # пример страницы https://www.petsonic.com/rascador-poste-con-rata-y-bola-para-gatos.html
        
        # название
        pr_name = doc.xpath(PRODUCT_NAME).map { |e| e.text.gsub(/,/, '.').strip }
        # цена:
        price_ar = doc.xpath(PRODUCT_PRICE).map { |e| e.text.match(/\d*\.\d*/) }
        # ссылки на картинки
        img_link_ar = doc.xpath(PRODUCT_IMG).map(&:text)


        writing_in_file_new_inf(pr_name, price_ar, img_link_ar)
    end

    def writing_in_file_new_inf(pr_name, price_ar, img_link_ar, weight_ar = nil)     
        puts("запись информации с карточки в файл")

       if weight_ar.class == price_ar.class 
           CSV.open(@file_name, "a") do |csv_f|
                price_ar.length.times do |i|
                    csv_f << [pr_name[0] + " - " + weight_ar[i], price_ar[i], img_link_ar[0]]  
                end
            end
       elsif weight_ar.class == nil.class
                
            weight_ar = "unknown weight"
            CSV.open(@file_name, "a") do |csv_f|
                price_ar.length.times do |i|
                    csv_f << [pr_name[0] + " - " + weight_ar, price_ar[i], img_link_ar[0]]  
                end
            end
       else
           puts("unknown case in method: writing_in_file_new_inf")
       end
    end

    def get_total_number_of_pages(link_to_category)

        doc = get_html(link_to_category +'?p=' + (2**20-1).to_s)
        total_num_of_pages = doc.xpath(TOTAL_NUM_OF_PAGES_V1).text

        if (total_num_of_pages == [] || total_num_of_pages == "") 
            doc = get_html(link_to_category)

            if !doc.xpath(LINK_TO_NEXT_PAGE).empty?

                total_num_of_pages = doc.xpath(TOTAL_NUM_OF_PAGES_V2)[-2].text
            else
                total_num_of_pages = 1 
            end
        end
        

        puts("Общее количество страниц в категории равно: " + total_num_of_pages.to_s)
        total_num_of_pages
    end

    def get_html(link_to_category)
        Nokogiri::HTML(URI.open(link_to_category))
    end
end


af = Parser_site.new
af.main_method()
